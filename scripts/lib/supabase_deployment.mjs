const PROJECT_REF_PATTERN = /^[a-z]{20}$/;

function configuredValue(name, value) {
  if (value === undefined || value === null || value === '') return '';
  if (typeof value !== 'string' || value.trim() !== value) {
    throw new Error(`${name} must not contain surrounding whitespace.`);
  }
  return value;
}

export function requireProjectRef(name, value, { optional = false } = {}) {
  const configured = configuredValue(name, value);
  if (!configured && optional) return '';
  if (!PROJECT_REF_PATTERN.test(configured)) {
    throw new Error(`${name} must be an exact 20-letter project ref.`);
  }
  return configured;
}

export function requireHttpsBaseUrl(
  name,
  value,
  { supabaseProjectRef = '' } = {},
) {
  const configured = configuredValue(name, value);
  if (!configured) {
    throw new Error(`${name} is required.`);
  }

  let parsed;
  try {
    parsed = new URL(configured);
  } catch {
    throw new Error(`${name} must be a valid HTTPS URL.`);
  }
  if (
    parsed.protocol !== 'https:' ||
    parsed.username ||
    parsed.password ||
    parsed.port ||
    (parsed.pathname !== '' && parsed.pathname !== '/') ||
    parsed.search ||
    parsed.hash ||
    configured.replace(/\/$/, '') !== parsed.origin
  ) {
    throw new Error(`${name} must be a credential-free HTTPS base URL.`);
  }
  if (
    supabaseProjectRef &&
    parsed.hostname !== `${supabaseProjectRef}.supabase.co`
  ) {
    throw new Error(`${name} does not match its configured Supabase project ref.`);
  }
  return parsed.origin;
}

export function resolveCompatibleKey({
  environment,
  currentName,
  legacyName,
  currentPrefix,
  requireCurrent = false,
  context,
}) {
  const current = configuredValue(currentName, environment[currentName]);
  const legacy = configuredValue(legacyName, environment[legacyName]);
  if (current && !current.startsWith(currentPrefix)) {
    throw new Error(`${currentName} must use the current ${currentPrefix} format.`);
  }
  if (requireCurrent && !current) {
    throw new Error(`${currentName} is required for ${context}.`);
  }
  if (!current && !legacy) {
    throw new Error(`${currentName} is required for ${context}.`);
  }
  return {
    value: current || legacy,
    source: current ? 'current' : 'legacy',
  };
}

export function supabaseBackendHeaders(
  key,
  { json = false, prefer = '' } = {},
) {
  if (
    !key ||
    typeof key.value !== 'string' ||
    !key.value ||
    !['current', 'legacy'].includes(key.source) ||
    (key.source === 'current' && !key.value.startsWith('sb_secret_')) ||
    (key.source === 'legacy' && key.value.startsWith('sb_secret_'))
  ) {
    throw new Error('Supabase backend key material is invalid.');
  }
  return {
    apikey: key.value,
    ...(key.source === 'legacy'
      ? { Authorization: `Bearer ${key.value}` }
      : {}),
    ...(json ? { 'Content-Type': 'application/json' } : {}),
    ...(prefer ? { Prefer: prefer } : {}),
  };
}

export function requireContactEmail(name, value) {
  const configured = configuredValue(name, value);
  if (
    configured.length > 254 ||
    !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(configured)
  ) {
    throw new Error(`${name} must be a valid contact email address.`);
  }
  return configured;
}

export function hostedSupabaseTarget(environment = process.env) {
  const appEnvironment = environment.APP_ENV;
  if (appEnvironment !== 'staging' && appEnvironment !== 'pilot') {
    throw new Error('APP_ENV must be exactly staging or pilot.');
  }

  const stagingProjectRef = requireProjectRef(
    'STAGING_SUPABASE_PROJECT_REF',
    environment.STAGING_SUPABASE_PROJECT_REF,
  );
  const pilotProjectRef = requireProjectRef(
    'PILOT_SUPABASE_PROJECT_REF',
    environment.PILOT_SUPABASE_PROJECT_REF,
    { optional: appEnvironment === 'staging' },
  );
  if (pilotProjectRef && stagingProjectRef === pilotProjectRef) {
    throw new Error('Staging and pilot Supabase project refs must be distinct.');
  }

  const projectRef =
    appEnvironment === 'staging' ? stagingProjectRef : pilotProjectRef;
  return {
    appEnvironment,
    projectRef,
    stagingProjectRef,
    pilotProjectRef,
    pilotContactEmail: requireContactEmail(
      'PILOT_CONTACT_EMAIL',
      environment.PILOT_CONTACT_EMAIL,
    ),
    supabaseUrl: requireHttpsBaseUrl('SUPABASE_URL', environment.SUPABASE_URL, {
      supabaseProjectRef: projectRef,
    }),
  };
}
