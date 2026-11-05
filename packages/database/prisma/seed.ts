import { PrismaClient } from '../src/generated/client';

const prisma = new PrismaClient();

const ROLES = [
  'GUEST',
  'REGISTERED_USER',
  'ASSISTANCE_APPLICANT',
  'MERCHANT',
  'MERCHANT_MANAGER',
  'COMMUNITY_VERIFIER',
  'ASSISTANCE_REVIEWER',
  'COMMITTEE_MEMBER',
  'CHARITY_PARTNER_REPRESENTATIVE',
  'CONTENT_MODERATOR',
  'ADMIN',
  'SUPER_ADMIN',
] as const;

const PERMISSIONS = [
  'users:read',
  'users:update',
  'roles:manage',

  'assistance:read',
  'assistance:review',
  'assistance:decide',
  'assistance:deliver',

  'verification:read',
  'verification:manage',

  'merchants:read',
  'merchants:verify',

  'offers:read',
  'offers:manage',
  'offers:redemptions:read',

  'groups:read',
  'groups:manage',
  'groups:finance:read',

  'files:read_public',
  'files:read_sensitive',

  'audit:read',
  'admin:access',
] as const;

const ROLE_PERMISSIONS: Record<string, string[]> = {
  SUPER_ADMIN: [...PERMISSIONS],

  ADMIN: [
    'users:read',
    'users:update',

    'assistance:read',
    'assistance:review',
    'assistance:decide',
    'assistance:deliver',

    'verification:read',
    'verification:manage',

    'merchants:read',
    'merchants:verify',

    'offers:read',
    'offers:manage',
    'offers:redemptions:read',

    'groups:read',
    'groups:manage',
    'groups:finance:read',

    'files:read_public',
    'files:read_sensitive',

    'audit:read',
    'admin:access',
  ],

  COMMITTEE_MEMBER: [
    'assistance:read',
    'assistance:review',
    'assistance:decide',
    'verification:read',
    'files:read_sensitive',
  ],

  ASSISTANCE_REVIEWER: [
    'assistance:read',
    'assistance:review',
    'verification:read',
    'files:read_sensitive',
  ],

  COMMUNITY_VERIFIER: [
    'verification:read',
    'verification:manage',
  ],

  MERCHANT: [
    'offers:read',
    'offers:manage',
    'offers:redemptions:read',
  ],

  MERCHANT_MANAGER: [
    'merchants:read',
    'offers:read',
    'offers:manage',
    'offers:redemptions:read',
  ],

  CONTENT_MODERATOR: [
    'merchants:read',
    'offers:read',
    'groups:read',
  ],

  CHARITY_PARTNER_REPRESENTATIVE: [
    'assistance:read',
    'assistance:deliver',
    'files:read_sensitive',
  ],

  REGISTERED_USER: [],
  ASSISTANCE_APPLICANT: [],
  GUEST: [],
};

const ADMIN_ID = '11111111-1111-4111-8111-111111111111';
const MERCHANT_USER_ID = '22222222-2222-4222-8222-222222222222';
const ORGANIZER_USER_ID = '33333333-3333-4333-8333-333333333333';

const MERCHANT_ID = '44444444-4444-4444-8444-444444444444';
const BRANCH_ID = '55555555-5555-4555-8555-555555555555';
const OFFER_ID = '66666666-6666-4666-8666-666666666666';
const GROUP_WEDDING_ID = '77777777-7777-4777-8777-777777777777';

async function main() {
  await prisma.$transaction(async (tx) => {
    // ------------------------------------------------------------------
    // 1) Permissions
    // ------------------------------------------------------------------
    const permissionIds = new Map<string, string>();

    for (const key of PERMISSIONS) {
      const permission = await tx.permission.upsert({
        where: { key },
        update: {},
        create: {
          key,
          description: `Permission: ${key}`,
        },
      });

      permissionIds.set(key, permission.id);
    }

    // ------------------------------------------------------------------
    // 2) Roles & Role Permissions
    // ------------------------------------------------------------------
    for (const roleName of ROLES) {
      const role = await tx.role.upsert({
        where: { name: roleName },
        update: {},
        create: {
          name: roleName,
          isSystem: true,
          description: `System role: ${roleName}`,
        },
      });

      const assignedPermissions = ROLE_PERMISSIONS[roleName] ?? [];

      for (const permissionKey of assignedPermissions) {
        const permissionId = permissionIds.get(permissionKey);
        if (!permissionId) continue;

        await tx.rolePermission.upsert({
          where: {
            roleId_permissionId: {
              roleId: role.id,
              permissionId,
            },
          },
          update: {},
          create: {
            roleId: role.id,
            permissionId,
          },
        });
      }
    }

    const roles = await tx.role.findMany();
    const roleMap = new Map(roles.map((role) => [role.name, role.id]));

    async function assignRole(userId: string, roleName: string) {
      const roleId = roleMap.get(roleName);
      if (!roleId) return;

      await tx.userRole.upsert({
        where: {
          userId_roleId: {
            userId,
            roleId,
          },
        },
        update: {},
        create: {
          userId,
          roleId,
        },
      });
    }

    // ------------------------------------------------------------------
    // 3) Geography — Amanat Al Asimah (Sana'a)
    // ------------------------------------------------------------------
    const governorate = await tx.governorate.upsert({
      where: { nameAr: 'أمانة العاصمة' },
      update: {},
      create: {
        nameAr: 'أمانة العاصمة',
        nameEn: 'Amanat Al Asimah',
        code: 'AMANAT_ALASIMAH',
      },
    });

    // قائمة مبدئية قابلة للمراجعة محلياً.
    // لا يجب اعتبارها قائمة نهائية دون تدقيق محلي.
    const directoratesInput = [
      { nameAr: 'مديرية صنعاء القديمة', nameEn: 'Old City Directorate' },
      { nameAr: 'مديرية السبعين', nameEn: 'Al Sabeen Directorate' },
      { nameAr: 'مديرية التحرير', nameEn: 'Al Tahrir Directorate' },
      { nameAr: 'مديرية الوحدة', nameEn: 'Al Wahda Directorate' },
      { nameAr: 'مديرية معين', nameEn: 'Maain Directorate' },
      { nameAr: 'مديرية شعوب', nameEn: 'Shuub Directorate' },
    ];

    const directorates = [];

    for (const directorate of directoratesInput) {
      const savedDirectorate = await tx.directorate.upsert({
        where: {
          governorateId_nameAr: {
            governorateId: governorate.id,
            nameAr: directorate.nameAr,
          },
        },
        update: {},
        create: {
          governorateId: governorate.id,
          nameAr: directorate.nameAr,
          nameEn: directorate.nameEn,
        },
      });

      directorates.push(savedDirectorate);
    }

    const sampleNeighborhoodNames = [
      'حارة تجريبية 1',
      'حارة تجريبية 2',
    ];

    for (const directorate of directorates.slice(0, 2)) {
      for (const neighborhoodName of sampleNeighborhoodNames) {
        await tx.neighborhood.upsert({
          where: {
            directorateId_nameAr: {
              directorateId: directorate.id,
              nameAr: neighborhoodName,
            },
          },
          update: {},
          create: {
            directorateId: directorate.id,
            nameAr: neighborhoodName,
            type: 'HARA',
          },
        });
      }
    }

    const firstDirectorate = directorates[0];
    if (!firstDirectorate) {
      throw new Error('No directorate was seeded.');
    }

    // ------------------------------------------------------------------
    // 4) Admin User
    // ------------------------------------------------------------------
    await tx.user.upsert({
      where: { id: ADMIN_ID },
      update: {},
      create: {
        id: ADMIN_ID,
        phone: '+967000000001',
        status: 'ACTIVE',
        privacyConsent: true,
        privacyConsentAt: new Date(),
        termsAcceptedAt: new Date(),
        passwordHash: process.env.SEED_ADMIN_PASSWORD_HASH ?? null,
      },
    });

    await tx.userProfile.upsert({
      where: { userId: ADMIN_ID },
      update: {},
      create: {
        userId: ADMIN_ID,
        fullName: 'مدير تجريبي',
        governorateId: governorate.id,
        directorateId: firstDirectorate.id,
      },
    });

    await assignRole(ADMIN_ID, 'ADMIN');
    await assignRole(ADMIN_ID, 'SUPER_ADMIN');

    // ------------------------------------------------------------------
    // 5) Merchant User
    // ------------------------------------------------------------------
    await tx.user.upsert({
      where: { id: MERCHANT_USER_ID },
      update: {},
      create: {
        id: MERCHANT_USER_ID,
        phone: '+967000000002',
        status: 'ACTIVE',
        privacyConsent: true,
        privacyConsentAt: new Date(),
        termsAcceptedAt: new Date(),
        passwordHash: process.env.SEED_MERCHANT_PASSWORD_HASH ?? null,
      },
    });

    await tx.userProfile.upsert({
      where: { userId: MERCHANT_USER_ID },
      update: {},
      create: {
        userId: MERCHANT_USER_ID,
        fullName: 'تاجر تجريبي',
        governorateId: governorate.id,
        directorateId: firstDirectorate.id,
      },
    });

    await assignRole(MERCHANT_USER_ID, 'MERCHANT');

    // ------------------------------------------------------------------
    // 6) Organizer User
    // ------------------------------------------------------------------
    await tx.user.upsert({
      where: { id: ORGANIZER_USER_ID },
      update: {},
      create: {
        id: ORGANIZER_USER_ID,
        phone: '+967000000003',
        status: 'ACTIVE',
        privacyConsent: true,
        privacyConsentAt: new Date(),
        termsAcceptedAt: new Date(),
        passwordHash: process.env.SEED_ORGANIZER_PASSWORD_HASH ?? null,
      },
    });

    await tx.userProfile.upsert({
      where: { userId: ORGANIZER_USER_ID },
      update: {},
      create: {
        userId: ORGANIZER_USER_ID,
        fullName: 'منظم تجريبي',
        governorateId: governorate.id,
        directorateId: firstDirectorate.id,
      },
    });

    await assignRole(ORGANIZER_USER_ID, 'REGISTERED_USER');

    // ------------------------------------------------------------------
    // 7) Merchant, Branch, Offer
    // ------------------------------------------------------------------
    const merchant = await tx.merchant.upsert({
      where: { id: MERCHANT_ID },
      update: {},
      create: {
        id: MERCHANT_ID,
        ownerId: MERCHANT_USER_ID,
        businessName: 'تاجر تجريبي — خدمات أعراس',
        category: 'HALL',
        description: 'بيانات تجريبية فقط لأغراض التطوير.',
        isVerified: true,
        status: 'VERIFIED',
      },
    });

    const branch = await tx.merchantBranch.upsert({
      where: { id: BRANCH_ID },
      update: {},
      create: {
        id: BRANCH_ID,
        merchantId: merchant.id,
        name: 'الفرع التجريبي',
        governorateId: governorate.id,
        directorateId: firstDirectorate.id,
        address: 'عنوان تجريبي داخل صنعاء',
        phone: '+967000000010',
        isActive: true,
      },
    });

    const now = new Date();
    const offerEnd = new Date(now.getTime() + 30 * 24 * 60 * 60 * 1000);

    await tx.offer.upsert({
      where: { id: OFFER_ID },
      update: {
        title: 'عرض تجريبي',
        description: 'عرض تجريبي غير حقيقي لأغراض التطوير.',
        originalPrice: '100000',
        discountedPrice: '80000',
        discountPercentage: '20.00',
        startDate: now,
        endDate: offerEnd,
        status: 'PENDING_REVIEW',
        eligibilityRule: 'للمقبلين على الزواج فقط.',
        requiresApproval: true,
      },
      create: {
        id: OFFER_ID,
        merchantId: merchant.id,
        branchId: branch.id,
        title: 'عرض تجريبي',
        description: 'عرض تجريبي غير حقيقي لأغراض التطوير.',
        originalPrice: '100000',
        discountedPrice: '80000',
        discountPercentage: '20.00',
        startDate: now,
        endDate: offerEnd,
        status: 'PENDING_REVIEW',
        maxRedemptions: 10,
        eligibilityRule: 'للمقبلين على الزواج فقط.',
        requiresApproval: true,
        terms: 'عرض تجريبي لأغراض التطوير فقط.',
      },
    });

    // ------------------------------------------------------------------
    // 8) Group Wedding & Organizer Participant
    // ------------------------------------------------------------------
    await tx.groupWedding.upsert({
      where: { id: GROUP_WEDDING_ID },
      update: {
        title: 'عرس جماعي تجريبي',
        description: 'مجموعة تجريبية لأغراض التطوير فقط.',
        status: 'OPEN_FOR_JOINING',
        venueText: 'مكان تجريبي داخل صنعاء',
        joinDeadline: offerEnd,
        confirmationDeadline: offerEnd,
        cancellationPolicyText: 'سياسة تجريبية: الانسحاب المجاني حتى تاريخ محدد.',
        sharedCostTotal: '500000',
        privateCostTotal: '0',
      },
      create: {
        id: GROUP_WEDDING_ID,
        organizerId: ORGANIZER_USER_ID,
        title: 'عرس جماعي تجريبي',
        description: 'مجموعة تجريبية لأغراض التطوير فقط.',
        status: 'OPEN_FOR_JOINING',
        visibility: 'INVITATION_ONLY',
        governorateId: governorate.id,
        directorateId: firstDirectorate.id,
        venueText: 'مكان تجريبي داخل صنعاء',
        plannedDate: new Date(now.getTime() + 60 * 24 * 60 * 60 * 1000),
        joinDeadline: offerEnd,
        confirmationDeadline: offerEnd,
        freeWithdrawalDeadline: offerEnd,
        cancellationPolicyText: 'سياسة تجريبية: الانسحاب المجاني حتى تاريخ محدد.',
        minParticipants: 2,
        maxParticipants: 5,
        sharedCostTotal: '500000',
        privateCostTotal: '0',
      },
    });

    await tx.groupParticipant.upsert({
      where: {
        groupId_userId: {
          groupId: GROUP_WEDDING_ID,
          userId: ORGANIZER_USER_ID,
        },
      },
      update: {
        status: 'CONFIRMED',
        isOrganizer: true,
        approvedByOrganizer: true,
        financialShare: '250000',
        guestCount: 10,
        paymentStatus: 'PENDING',
      },
      create: {
        groupId: GROUP_WEDDING_ID,
        userId: ORGANIZER_USER_ID,
        status: 'CONFIRMED',
        isOrganizer: true,
        approvedByOrganizer: true,
        financialShare: '250000',
        guestCount: 10,
        paymentStatus: 'PENDING',
        notes: 'مشارك تجريبي لأغراض التطوير.',
      },
    });
  });

  console.log('Seed completed successfully.');
}

main()
  .catch((error) => {
    console.error('Seed failed:', error);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
