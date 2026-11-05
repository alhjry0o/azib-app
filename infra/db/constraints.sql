-- =============================================================================
-- AZIB | عازب — Database Constraints, Triggers, and Integrity Rules
-- =============================================================================

BEGIN;

-- =============================================================================
-- 0) تحديث القيم المشتقة قبل إضافة القيود
-- =============================================================================

UPDATE offers o
SET "currentRedemptions" = (
  SELECT COUNT(*)::int
  FROM offer_redemptions r
  WHERE r."offerId" = o.id
    AND r.status::text IN ('ISSUED', 'REDEEMED')
);

UPDATE group_weddings gw
SET
  "currentParticipantsCount" = (
    SELECT COUNT(*)::int
    FROM group_participants gp
    WHERE gp."groupId" = gw.id
      AND gp."deletedAt" IS NULL
      AND gp.status::text IN ('INVITED', 'REQUESTED', 'ACCEPTED', 'CONFIRMED')
  ),
  "currentConfirmedCount" = (
    SELECT COUNT(*)::int
    FROM group_participants gp
    WHERE gp."groupId" = gw.id
      AND gp."deletedAt" IS NULL
      AND gp.status::text = 'CONFIRMED'
  ),
  "allocatedSharedCost" = (
    SELECT COALESCE(SUM(gp."financialShare"), 0)
    FROM group_participants gp
    WHERE gp."groupId" = gw.id
      AND gp."deletedAt" IS NULL
      AND gp.status::text = 'CONFIRMED'
  );

UPDATE assistance_fulfillments
SET "remainingAmount" = "approvedAmount" - "deliveredAmount";

-- =============================================================================
-- 1) دوال مساعدة
-- =============================================================================

CREATE OR REPLACE FUNCTION recalc_group_wedding_metrics(p_group_id uuid)
RETURNS void AS $$
BEGIN
  UPDATE group_weddings gw
  SET
    "currentParticipantsCount" = (
      SELECT COUNT(*)::int
      FROM group_participants gp
      WHERE gp."groupId" = p_group_id
        AND gp."deletedAt" IS NULL
        AND gp.status::text IN ('INVITED', 'REQUESTED', 'ACCEPTED', 'CONFIRMED')
    ),
    "currentConfirmedCount" = (
      SELECT COUNT(*)::int
      FROM group_participants gp
      WHERE gp."groupId" = p_group_id
        AND gp."deletedAt" IS NULL
        AND gp.status::text = 'CONFIRMED'
    ),
    "allocatedSharedCost" = (
      SELECT COALESCE(SUM(gp."financialShare"), 0)
      FROM group_participants gp
      WHERE gp."groupId" = p_group_id
        AND gp."deletedAt" IS NULL
        AND gp.status::text = 'CONFIRMED'
    )
  WHERE gw.id = p_group_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION maintain_group_participant_metrics()
RETURNS trigger AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    PERFORM recalc_group_wedding_metrics(OLD."groupId");
    RETURN OLD;
  ELSIF TG_OP = 'UPDATE' THEN
    IF NEW."groupId" IS DISTINCT FROM OLD."groupId" THEN
      PERFORM recalc_group_wedding_metrics(OLD."groupId");
    END IF;
    PERFORM recalc_group_wedding_metrics(NEW."groupId");
    RETURN NEW;
  ELSE
    PERFORM recalc_group_wedding_metrics(NEW."groupId");
    RETURN NEW;
  END IF;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION maintain_offer_current_redemptions()
RETURNS trigger AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    UPDATE offers
    SET "currentRedemptions" = (
      SELECT COUNT(*)::int
      FROM offer_redemptions
      WHERE "offerId" = OLD."offerId"
        AND status::text IN ('ISSUED', 'REDEEMED')
    )
    WHERE id = OLD."offerId";

    RETURN OLD;
  ELSIF TG_OP = 'UPDATE' THEN
    IF NEW."offerId" IS DISTINCT FROM OLD."offerId" THEN
      UPDATE offers
      SET "currentRedemptions" = (
        SELECT COUNT(*)::int
        FROM offer_redemptions
        WHERE "offerId" = OLD."offerId"
          AND status::text IN ('ISSUED', 'REDEEMED')
      )
      WHERE id = OLD."offerId";
    END IF;

    UPDATE offers
    SET "currentRedemptions" = (
      SELECT COUNT(*)::int
      FROM offer_redemptions
      WHERE "offerId" = NEW."offerId"
        AND status::text IN ('ISSUED', 'REDEEMED')
    )
    WHERE id = NEW."offerId";

    RETURN NEW;
  ELSE
    UPDATE offers
    SET "currentRedemptions" = (
      SELECT COUNT(*)::int
      FROM offer_redemptions
      WHERE "offerId" = NEW."offerId"
        AND status::text IN ('ISSUED', 'REDEEMED')
    )
    WHERE id = NEW."offerId";

    RETURN NEW;
  END IF;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION set_assistance_fulfillment_remaining()
RETURNS trigger AS $$
BEGIN
  NEW."remainingAmount" := NEW."approvedAmount" - NEW."deliveredAmount";
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION validate_group_wedding_closure()
RETURNS trigger AS $$
BEGIN
  IF NEW.status::text IN ('CONFIRMED', 'IN_PROGRESS', 'COMPLETED') THEN
    IF NEW."currentParticipantsCount" < NEW."minParticipants" THEN
      RAISE EXCEPTION 'Cannot confirm group wedding: current participants below minimum.';
    END IF;

    IF NEW."currentParticipantsCount" > NEW."maxParticipants" THEN
      RAISE EXCEPTION 'Cannot confirm group wedding: current participants above maximum.';
    END IF;

    IF NEW."allocatedSharedCost" <> NEW."sharedCostTotal" THEN
      RAISE EXCEPTION 'Cannot confirm group wedding: allocated shared cost must equal shared cost total.';
    END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION prevent_group_ledger_mutation()
RETURNS trigger AS $$
BEGIN
  RAISE EXCEPTION 'GroupLedgerEntry records are immutable. Use a new ADJUSTMENT entry instead.';
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION prevent_audit_log_mutation()
RETURNS trigger AS $$
BEGIN
  RAISE EXCEPTION 'AuditLog records are append-only and cannot be modified or deleted.';
END;
$$ LANGUAGE plpgsql;

-- =============================================================================
-- 2) Triggers
-- =============================================================================

DROP TRIGGER IF EXISTS group_participants_maintain_metrics ON group_participants;
CREATE TRIGGER group_participants_maintain_metrics
AFTER INSERT OR UPDATE OR DELETE ON group_participants
FOR EACH ROW EXECUTE FUNCTION maintain_group_participant_metrics();

DROP TRIGGER IF EXISTS offer_redemptions_maintain_count ON offer_redemptions;
CREATE TRIGGER offer_redemptions_maintain_count
AFTER INSERT OR UPDATE OR DELETE ON offer_redemptions
FOR EACH ROW EXECUTE FUNCTION maintain_offer_current_redemptions();

DROP TRIGGER IF EXISTS assistance_fulfillments_set_remaining ON assistance_fulfillments;
CREATE TRIGGER assistance_fulfillments_set_remaining
BEFORE INSERT OR UPDATE ON assistance_fulfillments
FOR EACH ROW EXECUTE FUNCTION set_assistance_fulfillment_remaining();

DROP TRIGGER IF EXISTS group_weddings_validate_closure ON group_weddings;
CREATE TRIGGER group_weddings_validate_closure
BEFORE INSERT OR UPDATE ON group_weddings
FOR EACH ROW EXECUTE FUNCTION validate_group_wedding_closure();

DROP TRIGGER IF EXISTS group_ledger_entries_prevent_update ON group_ledger_entries;
CREATE TRIGGER group_ledger_entries_prevent_update
BEFORE UPDATE ON group_ledger_entries
FOR EACH ROW EXECUTE FUNCTION prevent_group_ledger_mutation();

DROP TRIGGER IF EXISTS group_ledger_entries_prevent_delete ON group_ledger_entries;
CREATE TRIGGER group_ledger_entries_prevent_delete
BEFORE DELETE ON group_ledger_entries
FOR EACH ROW EXECUTE FUNCTION prevent_group_ledger_mutation();

DROP TRIGGER IF EXISTS audit_logs_prevent_update ON audit_logs;
CREATE TRIGGER audit_logs_prevent_update
BEFORE UPDATE ON audit_logs
FOR EACH ROW EXECUTE FUNCTION prevent_audit_log_mutation();

DROP TRIGGER IF EXISTS audit_logs_prevent_delete ON audit_logs;
CREATE TRIGGER audit_logs_prevent_delete
BEFORE DELETE ON audit_logs
FOR EACH ROW EXECUTE FUNCTION prevent_audit_log_mutation();

-- =============================================================================
-- 3) Partial Unique Indexes
-- =============================================================================

DROP INDEX IF EXISTS users_phone_active_unique;
CREATE UNIQUE INDEX users_phone_active_unique
ON users (phone)
WHERE "deletedAt" IS NULL;

DROP INDEX IF EXISTS users_email_active_unique;
CREATE UNIQUE INDEX users_email_active_unique
ON users (lower(email))
WHERE "deletedAt" IS NULL
  AND email IS NOT NULL;

DROP INDEX IF EXISTS assistance_requests_one_active_per_user;
CREATE UNIQUE INDEX assistance_requests_one_active_per_user
ON assistance_requests ("userId")
WHERE "deletedAt" IS NULL
  AND status::text IN (
    'DRAFT',
    'PENDING_DOCUMENTS',
    'SUBMITTED',
    'UNDER_COMMUNITY_VERIFICATION',
    'UNDER_COMMITTEE_REVIEW',
    'NEEDS_MORE_INFO',
    'APPROVED',
    'APPROVED_PARTIALLY',
    'APPEALED',
    'IN_DELIVERY'
  );

DROP INDEX IF EXISTS offer_redemptions_one_active_per_user_offer;
CREATE UNIQUE INDEX offer_redemptions_one_active_per_user_offer
ON offer_redemptions ("offerId", "userId")
WHERE status::text IN ('ISSUED', 'REDEEMED');

-- =============================================================================
-- 4) Check Constraints — Users & Consent
-- =============================================================================

ALTER TABLE users
DROP CONSTRAINT IF EXISTS users_privacy_consent_requires_timestamp;

ALTER TABLE users
ADD CONSTRAINT users_privacy_consent_requires_timestamp
CHECK ("privacyConsent" = false OR "privacyConsentAt" IS NOT NULL);

-- =============================================================================
-- 5) Check Constraints — Assistance
-- =============================================================================

ALTER TABLE assistance_requests
DROP CONSTRAINT IF EXISTS assistance_requests_amounts_nonnegative;

ALTER TABLE assistance_requests
ADD CONSTRAINT assistance_requests_amounts_nonnegative
CHECK (
  "targetAmount" >= 0
  AND ("incomeEstimate" IS NULL OR "incomeEstimate" >= 0)
  AND ("rentAmount" IS NULL OR "rentAmount" >= 0)
  AND ("monthlyObligationsAmount" IS NULL OR "monthlyObligationsAmount" >= 0)
  AND ("currentSupportAmount" IS NULL OR "currentSupportAmount" >= 0)
);

ALTER TABLE assistance_requests
DROP CONSTRAINT IF EXISTS assistance_requests_priority_score_range;

ALTER TABLE assistance_requests
ADD CONSTRAINT assistance_requests_priority_score_range
CHECK ("priorityScore" IS NULL OR "priorityScore" BETWEEN 0 AND 1000);

ALTER TABLE assistance_requests
DROP CONSTRAINT IF EXISTS assistance_requests_privacy_consent_requires_timestamp;

ALTER TABLE assistance_requests
ADD CONSTRAINT assistance_requests_privacy_consent_requires_timestamp
CHECK ("privacyConsent" = false OR "privacyConsentAt" IS NOT NULL);

ALTER TABLE assistance_items
DROP CONSTRAINT IF EXISTS assistance_items_estimated_cost_nonnegative;

ALTER TABLE assistance_items
ADD CONSTRAINT assistance_items_estimated_cost_nonnegative
CHECK ("estimatedCost" >= 0);

ALTER TABLE assistance_decisions
DROP CONSTRAINT IF EXISTS assistance_decisions_approved_amount_nonnegative;

ALTER TABLE assistance_decisions
ADD CONSTRAINT assistance_decisions_approved_amount_nonnegative
CHECK ("approvedAmount" IS NULL OR "approvedAmount" >= 0);

ALTER TABLE assistance_fulfillments
DROP CONSTRAINT IF EXISTS assistance_fulfillments_amounts_nonnegative;

ALTER TABLE assistance_fulfillments
ADD CONSTRAINT assistance_fulfillments_amounts_nonnegative
CHECK (
  "approvedAmount" >= 0
  AND "allocatedAmount" >= 0
  AND "deliveredAmount" >= 0
  AND "remainingAmount" >= 0
);

ALTER TABLE assistance_fulfillments
DROP CONSTRAINT IF EXISTS assistance_fulfillments_amounts_consistency;

ALTER TABLE assistance_fulfillments
ADD CONSTRAINT assistance_fulfillments_amounts_consistency
CHECK (
  "deliveredAmount" <= "allocatedAmount"
  AND "allocatedAmount" <= "approvedAmount"
  AND "remainingAmount" = "approvedAmount" - "deliveredAmount"
);

-- =============================================================================
-- 6) Check Constraints — Offers
-- =============================================================================

ALTER TABLE offers
DROP CONSTRAINT IF EXISTS offers_prices_nonnegative;

ALTER TABLE offers
ADD CONSTRAINT offers_prices_nonnegative
CHECK (
  "originalPrice" >= 0
  AND "discountedPrice" >= 0
);

ALTER TABLE offers
DROP CONSTRAINT IF EXISTS offers_discount_not_greater;

ALTER TABLE offers
ADD CONSTRAINT offers_discount_not_greater
CHECK ("discountedPrice" <= "originalPrice");

ALTER TABLE offers
DROP CONSTRAINT IF EXISTS offers_dates_valid;

ALTER TABLE offers
ADD CONSTRAINT offers_dates_valid
CHECK ("endDate" > "startDate");

ALTER TABLE offers
DROP CONSTRAINT IF EXISTS offers_current_redemptions_nonnegative;

ALTER TABLE offers
ADD CONSTRAINT offers_current_redemptions_nonnegative
CHECK ("currentRedemptions" >= 0);

ALTER TABLE offers
DROP CONSTRAINT IF EXISTS offers_max_redemptions_nonnegative;

ALTER TABLE offers
ADD CONSTRAINT offers_max_redemptions_nonnegative
CHECK ("maxRedemptions" IS NULL OR "maxRedemptions" >= 0);

ALTER TABLE offers
DROP CONSTRAINT IF EXISTS offers_redemptions_within_max;

ALTER TABLE offers
ADD CONSTRAINT offers_redemptions_within_max
CHECK ("maxRedemptions" IS NULL OR "currentRedemptions" <= "maxRedemptions");

-- =============================================================================
-- 7) Check Constraints — Group Weddings
-- =============================================================================

ALTER TABLE group_weddings
DROP CONSTRAINT IF EXISTS group_weddings_costs_nonnegative;

ALTER TABLE group_weddings
ADD CONSTRAINT group_weddings_costs_nonnegative
CHECK (
  "sharedCostTotal" >= 0
  AND "privateCostTotal" >= 0
  AND "allocatedSharedCost" >= 0
  AND ("costPerParticipant" IS NULL OR "costPerParticipant" >= 0)
);

ALTER TABLE group_weddings
DROP CONSTRAINT IF EXISTS group_weddings_participants_range;

ALTER TABLE group_weddings
ADD CONSTRAINT group_weddings_participants_range
CHECK (
  "minParticipants" >= 2
  AND "maxParticipants" <= 7
  AND "minParticipants" <= "maxParticipants"
);

ALTER TABLE group_weddings
DROP CONSTRAINT IF EXISTS group_weddings_counts_nonnegative;

ALTER TABLE group_weddings
ADD CONSTRAINT group_weddings_counts_nonnegative
CHECK (
  "currentParticipantsCount" >= 0
  AND "currentConfirmedCount" >= 0
);

ALTER TABLE group_weddings
DROP CONSTRAINT IF EXISTS group_weddings_counts_consistency;

ALTER TABLE group_weddings
ADD CONSTRAINT group_weddings_counts_consistency
CHECK (
  "currentConfirmedCount" <= "currentParticipantsCount"
  AND "currentParticipantsCount" <= "maxParticipants"
);

ALTER TABLE group_participants
DROP CONSTRAINT IF EXISTS group_participants_nonnegative_values;

ALTER TABLE group_participants
ADD CONSTRAINT group_participants_nonnegative_values
CHECK (
  "financialShare" >= 0
  AND "guestCount" >= 0
);

ALTER TABLE group_services
DROP CONSTRAINT IF EXISTS group_services_costs_nonnegative;

ALTER TABLE group_services
ADD CONSTRAINT group_services_costs_nonnegative
CHECK (
  "estimatedCost" >= 0
  AND ("finalCost" IS NULL OR "finalCost" >= 0)
);

ALTER TABLE group_expenses
DROP CONSTRAINT IF EXISTS group_expenses_amount_nonnegative;

ALTER TABLE group_expenses
ADD CONSTRAINT group_expenses_amount_nonnegative
CHECK ("amount" >= 0);

ALTER TABLE group_ledger_entries
DROP CONSTRAINT IF EXISTS group_ledger_entries_nonnegative;

ALTER TABLE group_ledger_entries
ADD CONSTRAINT group_ledger_entries_nonnegative
CHECK (
  "amount" >= 0
  AND "balanceAfter" >= 0
);

COMMIT;
