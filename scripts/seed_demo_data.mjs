import crypto from 'node:crypto';

const supabaseUrl = process.env.SUPABASE_URL?.replace(/\/$/, '');
const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
const demoPassword = process.env.DEMO_PASSWORD || 'DemoPass123!';

if (!supabaseUrl) {
  throw new Error('SUPABASE_URL is required');
}
if (!serviceRoleKey) {
  throw new Error('SUPABASE_SERVICE_ROLE_KEY is required');
}

assertLocalSupabaseUrl(supabaseUrl);

const scenarios = [
  {
    key: 'student',
    email: 'student@example.test',
    displayName: 'Maya Student Demo',
    timezone: 'Europe/Berlin',
    archetype: 'Focused Student',
    overallScore: 78,
    weekdayShape: 'school_or_work',
    bestEnergyWindow: 'morning',
    quietHoursStart: '21:30',
    quietHoursEnd: '07:00',
    baseline: {
      sleep: 7.8,
      steps: 7600,
      activity: 6,
      screen: 4.8,
      focus: 95,
      mood: 7,
      energy: 7,
      stress: 5,
    },
    priorities: [
      ['Protect study focus', 'Keep the first serious study block before messages and social apps.'],
      ['Stabilize school-night sleep', 'Avoid short nights before math-heavy mornings.'],
      ['Plan exams earlier', 'Move exam preparation into smaller weekday blocks.'],
    ],
    habits: [
      [
        'Morning review',
        'Review the top three school priorities before class.',
        [1, 1, 0, 1, -1, 1, 0],
        { kind: 'daily' },
      ],
      [
        'Phone away study block',
        'Keep the phone out of reach during the first focus block.',
        [0, -1, 0, -1, 0, 0, 0],
        { kind: 'weekdays', scheduledWeekdays: [1, 2, 3, 4, 5] },
      ],
      [
        'Evening shutdown',
        'Close school work and screens before quiet hours.',
        [1, 0, 1, 0, 1, 0, 0],
        { kind: 'weekly_target', weeklyTarget: 4 },
      ],
    ],
    schedule: [
      ['Math', 'Room 204', 1, '08:15', '09:45'],
      ['Study block', 'Library', 1, '10:15', '11:45'],
      ['Physics lab', 'Lab 2', 3, '13:00', '15:00'],
      ['Exam prep', 'Home desk', 4, '17:00', '18:00'],
      ['Recovery walk', 'Outside', 5, '16:00', '16:30'],
    ],
    tasks: [
      ['Finish math problem set', 'Submit the remaining proofs and review weak steps.', 'todo', 'high', 1, 60],
      ['Draft history outline', 'Turn the topic list into a two-page outline.', 'in_progress', 'medium', 2, 90],
      ['Prepare physics lab notes', 'Bring one question for the lab session.', 'cancelled', 'medium', 3, 45],
      ['Review flashcards', 'Twenty-minute spaced repetition block.', 'done', 'low', -1, 20],
    ],
    recommendations: [
      ['Protect the first study block', 'Your rated Focus sessions show stronger useful progress between 09:00 and 13:00.', 'Schedule block', 'focus', 0.86, 'high'],
      ['Keep exam preparation distributed', 'The upcoming exam and essay both need several manageable study blocks.', 'Plan prep', 'planning', 0.78, 'medium'],
      ['Keep the sleep window steady', 'Recent sleep estimates stay close to the saved eight-hour target.', 'Review recovery', 'recovery', 0.73, 'medium'],
    ],
    insights: [
      ['Morning focus is reliable', 'Rated sessions between 09:00 and 13:00 show higher useful progress in this sample.', 'focus', 0.84],
      ['Workload pressure is visible', 'Stress is moderately higher during the current exam-preparation week.', 'stress', 0.72],
    ],
    notifications: [
      ['Focus window approaching', 'Your best study window starts in 20 minutes.', 'reminder', 'high', 0, '/deep-work', 'unread'],
      ['Weekly review ready', 'Review the completed week before changing a habit.', 'coaching', 'medium', -1, '/weekly-review', 'read'],
      ['Earlier planning note', 'This dismissed row remains available to account export.', 'coaching', 'low', -3, '/insights', 'dismissed'],
    ],
    memories: [
      ['recurring_problem', 'Exam-week pressure', 'Dense deadline weeks need smaller preparation blocks and protected breaks.'],
      ['habit', 'Study pattern', 'The first focused block usually feels easier before lunch.'],
    ],
  },
  {
    key: 'worker',
    email: 'worker@example.test',
    displayName: 'Jon Worker Demo',
    timezone: 'Europe/Berlin',
    archetype: 'Busy Operator',
    overallScore: 72,
    weekdayShape: 'split_day',
    bestEnergyWindow: 'afternoon',
    quietHoursStart: '22:00',
    quietHoursEnd: '06:30',
    baseline: {
      sleep: 6.4,
      steps: 6200,
      activity: 5,
      screen: 7.1,
      focus: 82,
      mood: 6,
      energy: 6,
      stress: 7,
    },
    priorities: [
      ['Make room for deep work', 'Protect non-meeting time before deadline-heavy afternoons.'],
      ['Lower meeting recovery cost', 'Add transition buffers after intense calls.'],
      ['Keep tasks visible', 'Review the top three work commitments daily.'],
    ],
    habits: [
      ['Calendar triage', 'Review meetings and choose the real top three tasks.', [1, 1, 0, 1, 1, 1, 0]],
      ['Post-meeting reset', 'Take a short reset after high-context meetings.', [0, 1, 0, 1, 0, 1, 1]],
      ['Inbox shutdown', 'Stop reactive email checks before dinner.', [1, 0, 1, 0, 1, 0, 0]],
    ],
    schedule: [
      ['Team standup', 'Remote', 1, '09:00', '09:30'],
      ['Client sync', 'Remote', 2, '11:00', '12:00'],
      ['Deep work hold', 'Office', 3, '14:00', '15:30'],
      ['Project review', 'Remote', 4, '16:00', '17:00'],
      ['Admin sweep', 'Office', 5, '11:30', '12:00'],
    ],
    tasks: [
      ['Prepare stakeholder update', 'Create a concise summary and risk section.', 'todo', 'critical', 1],
      ['Review Q3 roadmap', 'Mark the decisions needed before planning.', 'in_progress', 'high', 2],
      ['Clean up inbox commitments', 'Turn open email promises into tasks.', 'todo', 'medium', 0],
      ['Send client recap', 'Capture decisions and owners from the last sync.', 'done', 'medium', -1],
    ],
    recommendations: [
      ['Hold one meeting-free block', 'Focus drops on days with meetings across every work segment.', 'Protect calendar', 'focus', 0.81, 'high'],
      ['Add transition buffers', 'Stress stays elevated after back-to-back calls.', 'Add reset', 'recovery', 0.76, 'medium'],
      ['Convert email promises into tasks', 'Untracked commitments are driving the highest-risk deadlines.', 'Create tasks', 'planning', 0.82, 'high'],
    ],
    insights: [
      ['Meetings fragment focus', 'Focus minutes fall when meetings occupy both morning and afternoon.', 'planning', 0.79],
      ['Resets reduce stress', 'Short reset blocks correlate with lower evening stress.', 'recovery', 0.69],
    ],
    notifications: [
      ['Deadline risk', 'Stakeholder update is still open and due soon.', 'deadline', 'critical', 0],
      ['Deep work hold', 'You have a 90-minute window available this afternoon.', 'reminder', 'medium', 0],
    ],
    memories: [
      ['pattern', 'Meeting pattern', 'Back-to-back calls usually reduce follow-through on planned work.'],
    ],
  },
  {
    key: 'recovery',
    email: 'recovery@example.test',
    displayName: 'Lea Recovery Demo',
    timezone: 'Europe/Berlin',
    archetype: 'Recovery Builder',
    overallScore: 68,
    weekdayShape: 'flexible',
    bestEnergyWindow: 'early_morning',
    quietHoursStart: '20:45',
    quietHoursEnd: '07:30',
    baseline: {
      sleep: 7.8,
      steps: 5200,
      activity: 4,
      screen: 3.6,
      focus: 54,
      mood: 6,
      energy: 5,
      stress: 4,
    },
    priorities: [
      ['Rebuild consistent energy', 'Keep daily expectations realistic while energy stabilizes.'],
      ['Move gently every day', 'Use short walks rather than intense workouts.'],
      ['Protect evening recovery', 'Keep the last hour of the day quiet and predictable.'],
    ],
    habits: [
      ['Morning light', 'Get outdoor light before the first work block.', [1, 1, 1, 1, 0, 1, 1]],
      ['Gentle walk', 'Ten to twenty minutes of easy movement.', [1, 0, 1, 1, 1, 1, 0]],
      ['Recovery shutdown', 'Start the low-stimulation evening routine.', [1, 1, 1, 0, 1, 1, 1]],
    ],
    schedule: [
      ['Morning reset', 'Outside', 1, '08:00', '08:20'],
      ['Admin block', 'Home', 2, '10:00', '11:00'],
      ['Gentle movement', 'Park', 3, '15:30', '16:00'],
      ['Quiet evening', 'Home', 4, '20:45', '21:30'],
      ['Weekly review', 'Home', 7, '18:00', '18:30'],
    ],
    tasks: [
      ['Plan low-energy day fallback', 'Write the minimum viable plan for tired mornings.', 'todo', 'medium', 1],
      ['Prepare recovery routine', 'Put evening routine items in one visible place.', 'in_progress', 'medium', 2],
      ['Book light movement slot', 'Choose a walk window before the day fills up.', 'todo', 'low', 0],
      ['Reflect on energy pattern', 'Note what helped energy feel steadier.', 'done', 'low', -1],
    ],
    recommendations: [
      ['Keep tomorrow smaller', 'Energy is improving, but high-load days still reduce recovery.', 'Trim plan', 'recovery', 0.83, 'high'],
      ['Use a gentle walk reset', 'Movement consistency is better than intensity for this scenario.', 'Add walk', 'movement', 0.77, 'medium'],
      ['Plan a minimum viable day', 'A fallback plan reduces stress on lower-energy mornings.', 'Create fallback', 'planning', 0.74, 'medium'],
    ],
    insights: [
      ['Shutdown protects energy', 'Recovery scores are higher after low-stimulation evenings.', 'sleep', 0.81],
      ['Small walks are enough', 'Gentle movement days have steadier mood without higher stress.', 'movement', 0.75],
    ],
    notifications: [
      ['Recovery window', 'Start the quiet evening routine in about 30 minutes.', 'reminder', 'medium', 0],
      ['Gentle movement cue', 'A short walk is enough today.', 'coaching', 'low', 0],
    ],
    memories: [
      ['habit', 'Recovery habit', 'Evening shutdown is a strong support signal.'],
    ],
  },
];

await main();

async function main() {
  const users = await listAdminUsers();
  const seeded = [];

  for (const scenario of scenarios) {
    const existing = users.find(
      (user) => user.email?.toLowerCase() === scenario.email.toLowerCase(),
    );
    if (existing) {
      await deleteDemoAccount(existing.id, scenario.email);
    }
    const user = await createAdminUser(scenario);
    await seedScenario(user.id, scenario);
    seeded.push(`${scenario.email} (${scenario.displayName})`);
  }

  console.log('');
  console.log('Demo data seeded for local Supabase.');
  console.log(`Password for all demo users: ${demoPassword}`);
  for (const item of seeded) {
    console.log(`- ${item}`);
  }
}

function assertLocalSupabaseUrl(value) {
  const parsed = new URL(value);
  const isLocalHost =
    parsed.hostname === '127.0.0.1' || parsed.hostname === 'localhost';
  if (parsed.protocol !== 'http:' || !isLocalHost || parsed.port !== '54321') {
    throw new Error(
      `Refusing to seed non-local Supabase URL: ${value}. Expected http://127.0.0.1:54321 or http://localhost:54321.`,
    );
  }
}

async function listAdminUsers() {
  const allUsers = [];
  for (let page = 1; page <= 20; page += 1) {
    const response = await adminRequest(
      `/auth/v1/admin/users?page=${page}&per_page=100`,
      { method: 'GET' },
      'list local auth users',
    );
    const users = Array.isArray(response) ? response : response.users || [];
    allUsers.push(...users);
    if (users.length < 100) {
      break;
    }
  }
  return allUsers;
}

async function createAdminUser(scenario) {
  return adminRequest(
    '/auth/v1/admin/users',
    {
      method: 'POST',
      body: JSON.stringify({
        email: scenario.email,
        password: demoPassword,
        email_confirm: true,
        user_metadata: {
          display_name: scenario.displayName,
          demo_scenario: scenario.key,
        },
      }),
    },
    `create demo user ${scenario.email}`,
  );
}

async function deleteDemoAccount(userId, email) {
  const result = await restRequest(
    'rpc/delete_account_v1',
    {
      method: 'POST',
      body: JSON.stringify({
        p_user_id: userId,
        p_confirmation: 'DELETE',
      }),
    },
    `replace local demo account ${email}`,
  );
  if (
    !result ||
    result.deleted !== true ||
    result.not_found !== false ||
    result.user_id !== userId
  ) {
    throw new Error(
      `Could not confirm local demo account replacement for ${email}.`,
    );
  }
}

async function adminRequest(path, options, description) {
  return request(
    `${supabaseUrl}${path}`,
    {
      ...options,
      headers: {
        apikey: serviceRoleKey,
        Authorization: `Bearer ${serviceRoleKey}`,
        'Content-Type': 'application/json',
        ...(options.headers || {}),
      },
    },
    description,
  );
}

async function seedScenario(userId, scenario) {
  const now = new Date();
  const today = dateOnly(now);
  const weekKey = isoWeekKey(now);
  const reviewWeekStart = addDays(startOfIsoWeek(now), -7);
  const metadata = { source: 'demo_seed_v2', scenario: scenario.key };
  const intakeRequestId = deterministicUuid(
    `demo-seed:intake-request:${userId}:intake-v1`,
  );
  const intakeResponseId = deterministicUuid(
    `demo-seed:intake-response:${userId}:intake-v1`,
  );
  const onboardingSnapshotId = deterministicUuid(
    `demo-seed:onboarding-snapshot:${userId}:intake-v1`,
  );
  await upsertRows(
    'profiles',
    [
      {
        id: userId,
        email: scenario.email,
        display_name: scenario.displayName,
        timezone: scenario.timezone,
        role: 'user',
        auth_provider: 'email',
        onboarding_completed_at: now.toISOString(),
        setup_revision: 1,
        daily_preparation_budget_minutes: null,
        updated_at: now.toISOString(),
      },
    ],
    'id',
  );

  await upsertRows(
    'notification_preferences',
    [
      {
        user_id: userId,
        focus_prompts_enabled: true,
        recovery_prompts_enabled: true,
        weekly_summary_enabled: true,
        quiet_hours_start: scenario.quietHoursStart,
        quiet_hours_end: scenario.quietHoursEnd,
        in_app_delivery_enabled: false,
        in_app_delivery_consent_version: null,
        in_app_delivery_consented_at: null,
        in_app_delivery_disabled_at: null,
        delivery_settings_request_id: null,
        delivery_settings_request_fingerprint: null,
        daily_notification_limit: 2,
        updated_at: now.toISOString(),
      },
    ],
    'user_id',
  );

  await insertRows('intake_responses', [
    {
      id: intakeResponseId,
      user_id: userId,
      version: 'intake-v1',
      request_id: intakeRequestId,
      base_revision: 0,
      revision: 1,
      state: 'applied',
      responses: {
        display_name: scenario.displayName,
        weekday_shape: scenario.weekdayShape,
        best_energy_window: scenario.bestEnergyWindow,
        routines: [],
        fixed_commitments: [],
      },
      metadata: {
        source: 'onboarding',
        request_metadata: metadata,
        snapshot_id: onboardingSnapshotId,
      },
      completed_at: now.toISOString(),
      updated_at: now.toISOString(),
    },
  ]);

  const dailyLogs = buildDailyLogs(userId, scenario, now, metadata);
  await insertRows('daily_logs', dailyLogs);
  await insertRows(
    'behavioral_events',
    buildBehavioralEvents(userId, scenario, dailyLogs, metadata),
  );

  const taskRows = scenario.tasks.map(
    (
      [title, description, status, priority, offsetDays, estimatedMinutes],
      index,
    ) => {
      const terminalAt = atHour(addDays(reviewWeekStart, 1 + index), 16, 0);
      return {
        id: deterministicUuid(`demo-seed:task:${userId}:${index}`),
        user_id: userId,
        title,
        description,
        status,
        priority,
        deadline: atHour(addDays(now, offsetDays), 16, 0),
        estimated_minutes: estimatedMinutes ?? [45, 60, 30, 20][index] ?? 30,
        completed_at: status === 'done' ? terminalAt : null,
        cancelled_at: status === 'cancelled' ? terminalAt : null,
        source: 'demo_seed',
        metadata,
        created_at: addDays(reviewWeekStart, -10 + index).toISOString(),
        updated_at:
          status === 'done' || status === 'cancelled'
            ? terminalAt
            : addDays(now, -index).toISOString(),
      };
    },
  );
  await insertRows('tasks', taskRows);

  await insertRows(
    'schedule_items',
    scenario.schedule.map(([title, location, weekday, startsAt, endsAt], index) => ({
      id: deterministicUuid(`demo-seed:schedule:${userId}:${index}`),
      user_id: userId,
      title,
      location,
      weekday,
      starts_at: startsAt,
      ends_at: endsAt,
      color: ['#1f9d8a', '#3266cc', '#b86b00', '#6f51d9'][index % 4],
      source: 'demo_seed',
      notes: `Demo ${scenario.key} schedule block`,
      metadata,
    })),
  );

  const habitRows = scenario.habits.map(
    ([title, description, , cadenceConfig], index) => {
      const cadence = habitCadenceProjection(cadenceConfig);
      return {
        id: deterministicUuid(`demo-seed:habit:${userId}:${index}`),
        user_id: userId,
        title,
        description,
        frequency: cadence.frequency,
        target: cadence.target,
        active: true,
        metadata: {
          ...metadata,
          contract_version: 'habit-v1',
          cadence: cadence.kind,
          ...(cadence.scheduledWeekdays.length > 0
            ? { scheduled_weekdays: cadence.scheduledWeekdays }
            : {}),
          lifecycle: 'active',
          started_on: dateOnly(addDays(reviewWeekStart, -45)),
        },
        created_at: addDays(reviewWeekStart, -45 + index).toISOString(),
        updated_at: addDays(reviewWeekStart, -20 + index).toISOString(),
      };
    },
  );
  await insertRows('habits', habitRows);
  await insertRows(
    'habit_logs',
    buildHabitLogs(userId, scenario, habitRows, now),
  );
  if (scenario.key === 'worker') {
    await restRequest(
      `habits?id=eq.${habitRows[2].id}`,
      {
        method: 'PATCH',
        body: JSON.stringify({
          active: false,
          metadata: {
            ...habitRows[2].metadata,
            lifecycle: 'paused',
          },
          updated_at: now.toISOString(),
        }),
        headers: { Prefer: 'return=minimal' },
      },
      'pause demo habit after inserting its history',
    );
  }
  if (scenario.key === 'student') {
    const focusEvidence = buildStudentFocusEvidence(
      userId,
      taskRows,
      habitRows,
      now,
    );
    await insertRows('focus_sessions', focusEvidence.sessions);
    await insertRows(
      'focus_session_reflections',
      focusEvidence.reflections,
    );
  }

  await insertRows(
    'notifications',
    scenario.notifications.map(
      ([title, message, type, priority, offsetDays, actionUrl, lifecycle], index) => {
        const lifecycleTimestamp = addDays(now, -index).toISOString();
        const state = lifecycle ?? (index > 0 ? 'read' : 'unread');
        const isRead = state === 'read' || state === 'dismissed';
        const isDismissed = state === 'dismissed';
        return {
          id: deterministicUuid(`demo-seed:notification:${userId}:${index}`),
          user_id: userId,
          title,
          message,
          type,
          priority,
          is_read: isRead,
          read_at: isRead ? lifecycleTimestamp : null,
          dismissed_at: isDismissed ? lifecycleTimestamp : null,
          action_url: actionUrl ?? null,
          due_at: atHour(addDays(now, offsetDays), 15 + index, 0),
          metadata,
          created_at: lifecycleTimestamp,
          updated_at: lifecycleTimestamp,
        };
      },
    ),
  );

  await insertRows(
    'memory_entries',
    [
      {
        id: deterministicUuid(`demo-seed:memory:${userId}:setup-energy`),
        user_id: userId,
        type: 'pattern',
        title: 'Best energy window',
        content: scenario.bestEnergyWindow,
        strength: 0.8,
        evidence: [{ source: 'intake-v1', field: 'best_energy_window' }],
        metadata: {
          ...metadata,
          source: 'intake-v1',
          managed_by: 'setup',
          setup_state: 'active',
          setup_item_id: deterministicUuid(
            `demo-seed:memory-item:${userId}:best-energy-window`,
          ),
          revision: 1,
        },
        last_seen_at: now.toISOString(),
        created_at: addDays(now, -40).toISOString(),
        updated_at: now.toISOString(),
      },
      ...scenario.memories.map(([type, title, content], index) => ({
        id: deterministicUuid(`demo-seed:memory:${userId}:${index}`),
        user_id: userId,
        type,
        title,
        content,
        strength: 0.72 - index * 0.08,
        evidence: [{ source: 'demo_seed', scenario: scenario.key }],
        metadata,
        last_seen_at: addDays(now, -index).toISOString(),
        created_at: addDays(now, -30 + index).toISOString(),
        updated_at: addDays(now, -index).toISOString(),
      })),
    ],
  );

  await insertRows(
    'ai_insights',
    scenario.insights.map(([title, description, category, confidence], index) => ({
      id: deterministicUuid(`demo-seed:insight:${userId}:${index}`),
      user_id: userId,
      title,
      description,
      category,
      priority: index === 0 ? 'high' : 'medium',
      recommendation: scenario.recommendations[index]?.[0] ?? null,
      confidence,
      source: 'demo_seed',
      metadata,
      created_at: addDays(now, -index).toISOString(),
    })),
  );

  await insertRows(
    'recommendations',
    scenario.recommendations.map(
      ([title, reason, actionLabel, category, confidence, priority], index) => ({
        id: deterministicUuid(`demo-seed:recommendation:${userId}:${index}`),
        user_id: userId,
        title,
        reason,
        action_label: actionLabel,
        category,
        confidence,
        status: index === 2 ? 'accepted' : 'new',
        priority,
        metadata: {
          ...metadata,
          model: null,
          source_engine_version: 'demo-seed-v1',
        },
        generated_at: addDays(now, -index).toISOString(),
        updated_at: addDays(now, -index).toISOString(),
      }),
    ),
  );

  await insertRows('skillset_profiles', [
    {
      id: deterministicUuid(`demo-seed:skillset:${userId}:current`),
      user_id: userId,
      overall_score: scenario.overallScore,
      archetype: scenario.archetype,
      scores: [
        { name: 'Focus', score: scenario.baseline.focus > 90 ? 84 : 68 },
        { name: 'Recovery', score: Math.round(scenario.baseline.sleep * 10) },
        { name: 'Planning', score: scenario.key === 'worker' ? 74 : 81 },
        { name: 'Movement', score: scenario.baseline.activity * 10 },
      ],
      generated_at: now.toISOString(),
    },
  ]);

  await insertRows('coach_messages', [
    {
      id: deterministicUuid(`demo-seed:legacy-coach-message:${userId}:user`),
      user_id: userId,
      role: 'user',
      content: 'What should I pay attention to today?',
      metadata,
      created_at: addDays(now, -1).toISOString(),
    },
    {
      id: deterministicUuid(`demo-seed:legacy-coach-message:${userId}:assistant`),
      user_id: userId,
      role: 'assistant',
      content: scenario.recommendations[0][1],
      metadata,
      created_at: addDays(now, -1).toISOString(),
    },
  ]);

  const snapshotRows = [
    {
      id: onboardingSnapshotId,
      user_id: userId,
      scope: 'onboarding',
      period_key: 'setup:intake-v1',
      summary: {
        best_energy_window: scenario.bestEnergyWindow,
        fixed_commitment_count: 0,
        existing_habit_count: 0,
        routine_candidate_count: 0,
        active_habit_count: 0,
      },
      signals: {},
      source: 'backend',
      metadata: {
        source: 'intake-v1',
        managed_by: 'setup',
        intake_response_id: intakeResponseId,
        request_id: intakeRequestId,
        revision: 1,
      },
      generated_at: now.toISOString(),
    },
    {
      id: deterministicUuid(`demo-seed:daily-snapshot:${userId}:${today}`),
      user_id: userId,
      scope: 'daily',
      period_key: today,
      summary: {
        focus_hint: scenario.recommendations[0][0],
        recovery_hint: scenario.recommendations[1][0],
        risk_flags: scenario.baseline.stress >= 7 ? ['deadline_pressure'] : [],
      },
      signals: {
        input_counts: {
          daily_logs: dailyLogs.length,
          behavioral_events: dailyLogs.length * 5,
          tasks: scenario.tasks.length,
          habits: scenario.habits.length,
        },
      },
      source: 'demo_seed',
      metadata,
      generated_at: now.toISOString(),
    },
    {
      id: deterministicUuid(`demo-seed:weekly-snapshot:${userId}:${weekKey}`),
      user_id: userId,
      scope: 'weekly',
      period_key: weekKey,
      summary: {
        weekly_theme: scenario.priorities[0][0],
        next_focus: scenario.recommendations[0][0],
      },
      signals: {
        input_counts: {
          daily_logs: dailyLogs.length,
          recommendations: scenario.recommendations.length,
        },
      },
      source: 'demo_seed',
      metadata,
      generated_at: now.toISOString(),
    },
  ];
  await upsertRows(
    'user_state_snapshots',
    [snapshotRows[0]],
    'user_id,scope,period_key',
  );
  await upsertRows(
    'user_state_snapshots',
    snapshotRows.slice(1),
    'user_id,scope,period_key',
  );
}

function buildDailyLogs(userId, scenario, now, metadata) {
  if (scenario.key === 'student') {
    return buildStudentDailyLogs(userId, scenario, now, metadata);
  }
  const wave = [-1, 0, 1, 0, 2, -1, 1];
  return Array.from({ length: 21 }, (_, index) => {
    const offset = index - 20;
    const date = addDays(now, offset);
    const variation = wave[index % wave.length];
    const sleep = clampNumber(scenario.baseline.sleep + variation * 0.25, 4.5, 9.5);
    const energy = clampInt(scenario.baseline.energy + variation, 1, 10);
    const baselineStress = clampInt(
      scenario.baseline.stress + (index % 5 === 0 ? 1 : 0) - (variation > 0 ? 1 : 0),
      1,
      10,
    );
    const stress =
      scenario.key === 'student' && index % 2 === 0 ? 8 : baselineStress;
    const mood = clampInt(scenario.baseline.mood + Math.sign(variation), 1, 10);
    const focus = clampInt(
      scenario.baseline.focus + variation * 12 - (stress > 7 ? 16 : 0),
      10,
      240,
    );
    const activity = clampInt(scenario.baseline.activity + Math.sign(variation), 0, 10);
    const entryDate = dateOnly(date);
    const id = deterministicUuid(`demo-seed:daily-log:${userId}:${entryDate}`);
    const useStructuredCapture = scenario.key === 'student' && offset >= -14;

    if (useStructuredCapture) {
      const structuredSleep = Math.round(sleep * 2) / 2;
      const morningCapturedAt = atHour(date, 6, 30);
      const eveningCapturedAt = atHour(date, 20, 30);
      const estimatedSleepMinutes = structuredSleep * 60;
      const estimatedSleepStartedAt = new Date(
        Date.parse(morningCapturedAt) - estimatedSleepMinutes * 60_000,
      ).toISOString();
      const previousEntryDate = dateOnly(addDays(date, -1));
      const eveningCapture = {
        branch_version: 'daily-capture-v4',
        capture_kind: 'evening',
        entry_date: entryDate,
        capture_id: deterministicUuid(
          `demo-seed:evening-capture:${userId}:${entryDate}`,
        ),
        captured_at: eveningCapturedAt,
        mood,
        energy,
        stress_intensity: stress,
        stress_intensity_label: stressIntensityLabel(stress),
        stress_source:
          stress >= 7 && scenario.key === 'student'
            ? 'private_emotional'
            : stress >= 7
              ? 'workload'
              : 'external_environment',
        stress_controllability:
          stress >= 7 && scenario.key === 'student'
            ? 'hardly_controllable'
            : stress >= 7
              ? 'partly_controllable'
              : 'mostly_controllable',
        planned_sleep_time: '22:30',
        sleep_target_minutes: 480,
        focus_band: focusBand(focus),
        tomorrow_priority:
          scenario.priorities[index % scenario.priorities.length][0],
        ...(offset === 0
          ? {
              reflection_note:
                'The first focused block worked better than switching between tasks.',
              specific_blocker: 'Late messages interrupted the second study block.',
            }
          : {}),
      };
      const morningCapture = {
        branch_version: 'daily-capture-v4',
        capture_kind: 'morning',
        entry_date: entryDate,
        capture_id: deterministicUuid(
          `demo-seed:morning-capture:${userId}:${entryDate}`,
        ),
        captured_at: morningCapturedAt,
        estimated_sleep_started_at: estimatedSleepStartedAt,
        woke_at: morningCapturedAt,
        estimated_sleep_minutes: estimatedSleepMinutes,
        sleep_target_minutes: 480,
        ...(offset > -14
          ? {
              source_evening_capture_id: deterministicUuid(
                `demo-seed:evening-capture:${userId}:${previousEntryDate}`,
              ),
            }
          : {}),
        sleep_hours: structuredSleep,
        sleep_quality: clampInt(Math.round(structuredSleep), 1, 10),
        current_energy: energy,
        day_shape: stress >= 7 ? 'constrained' : 'normal',
      };
      return {
        id,
        user_id: userId,
        entry_date: entryDate,
        sleep_hours: structuredSleep,
        steps: null,
        activity_level: null,
        screen_time_hours: null,
        focus_minutes: null,
        mood_score: mood,
        mood_label: moodLabel(mood),
        energy_level: energy,
        stress_level: stress,
        nutrition_notes: null,
        day_focus: null,
        reflection: null,
        source: 'quick_check_in',
        metadata: {
          ...metadata,
          capture_version: 'daily-capture-v4',
          captures: {
            evening: eveningCapture,
            morning: morningCapture,
          },
        },
        created_at: morningCapturedAt,
        updated_at: eveningCapturedAt,
      };
    }

    return {
      id,
      user_id: userId,
      entry_date: entryDate,
      sleep_hours: Number(sleep.toFixed(1)),
      steps: scenario.baseline.steps + variation * 450 + (index % 3) * 180,
      activity_level: activity,
      screen_time_hours: Number(
        clampNumber(scenario.baseline.screen - variation * 0.2, 1.5, 9).toFixed(1),
      ),
      focus_minutes: focus,
      mood_score: mood,
      mood_label: moodLabel(mood),
      energy_level: energy,
      stress_level: stress,
      nutrition_notes: index % 4 === 0 ? 'Regular meals, lighter evening.' : null,
      day_focus: scenario.priorities[index % scenario.priorities.length][0],
      reflection: `Demo ${scenario.key} signal day ${index + 1}.`,
      source: 'demo_seed',
      metadata,
      created_at: atHour(date, 20, 0),
      updated_at: atHour(date, 20, 15),
    };
  });
}

function buildStudentDailyLogs(userId, scenario, now, metadata) {
  const timezone = scenario.timezone;
  const today = localDateOnly(now, timezone);
  const sleepMinutesByDay = [465, 480, 450, 495, 475, 505, 490];
  const weekdayStress = [5, 5, 6, 5, 4, 3, 3];

  return Array.from({ length: 43 }, (_, index) => {
    const offset = index - 42;
    const entryDate = addDateOnlyDays(today, offset);
    const dateAtNoon = new Date(`${entryDate}T12:00:00.000Z`);
    const weekday = isoWeekday(dateAtNoon);
    const isWeekend = weekday >= 6;
    const recentDeadlinePressure = offset >= -8 && !isWeekend ? 1 : 0;
    const oneBusyDay = index % 13 === 6 ? 1 : 0;
    const stress = clampInt(
      weekdayStress[weekday - 1] + recentDeadlinePressure + oneBusyDay,
      3,
      8,
    );
    const sleepMinutes = clampInt(
      sleepMinutesByDay[index % sleepMinutesByDay.length] -
        (stress >= 7 ? 15 : 0),
      435,
      510,
    );
    const sleepHours = sleepMinutes / 60;
    const sleepQuality = clampInt(
      6 + (sleepMinutes - 450) / 30 - (stress >= 7 ? 1 : 0),
      6,
      9,
    );
    const energy = clampInt(
      6 + (sleepMinutes - 450) / 45 - (stress >= 7 ? 1 : 0),
      5,
      8,
    );
    const mood = clampInt(
      7 + (isWeekend ? 1 : 0) - (stress >= 7 ? 1 : 0),
      6,
      8,
    );
    const wakeClock = isWeekend
      ? index % 2 === 0
        ? '08:00'
        : '08:20'
      : ['07:00', '07:10', '07:20'][index % 3];
    const wokeAt = zonedDateTime(entryDate, wakeClock, timezone);
    const morningCapturedAt = addMinutes(wokeAt, 10);
    const estimatedSleepStartedAt = addMinutes(wokeAt, -sleepMinutes);
    const plannedSleepTime = isWeekend ? '23:30' : '23:00';
    const eveningCapturedAt = zonedDateTime(entryDate, '21:15', timezone);
    const id = deterministicUuid(`demo-seed:daily-log:${userId}:${entryDate}`);
    const morningCaptureId = deterministicUuid(
      `demo-seed:morning-capture:${userId}:${entryDate}`,
    );
    const previousEntryDate = addDateOnlyDays(entryDate, -1);
    const morningCapture = {
      branch_version: 'daily-capture-v4',
      capture_kind: 'morning',
      entry_date: entryDate,
      capture_id: morningCaptureId,
      captured_at: morningCapturedAt.toISOString(),
      estimated_sleep_started_at: estimatedSleepStartedAt.toISOString(),
      woke_at: wokeAt.toISOString(),
      estimated_sleep_minutes: sleepMinutes,
      sleep_target_minutes: 480,
      source_evening_capture_id: deterministicUuid(
        `demo-seed:evening-capture:${userId}:${previousEntryDate}`,
      ),
      sleep_hours: sleepHours,
      sleep_quality: sleepQuality,
      current_energy: energy,
      day_shape: stress >= 7 ? 'constrained' : isWeekend ? 'flexible' : 'normal',
    };
    const includeEvening = offset < 0;
    const eveningCapture = includeEvening
      ? {
          branch_version: 'daily-capture-v4',
          capture_kind: 'evening',
          entry_date: entryDate,
          capture_id: deterministicUuid(
            `demo-seed:evening-capture:${userId}:${entryDate}`,
          ),
          captured_at: eveningCapturedAt.toISOString(),
          mood,
          energy,
          stress_intensity: stress,
          stress_intensity_label: stressIntensityLabel(stress),
          ...(stress >= 5
            ? {
                stress_source: 'workload',
                stress_controllability:
                  stress >= 7 ? 'partly_controllable' : 'mostly_controllable',
              }
            : {}),
          planned_sleep_time: plannedSleepTime,
          sleep_target_minutes: 480,
          tomorrow_priority:
            scenario.priorities[index % scenario.priorities.length][0],
          ...(offset === -1
            ? {
                reflection_note:
                  'The morning study block was productive, and the afternoon plan stayed manageable.',
                specific_blocker:
                  'A longer campus day made the final review block harder to start.',
              }
            : {}),
        }
      : null;
    return {
      id,
      user_id: userId,
      entry_date: entryDate,
      sleep_hours: sleepHours,
      steps: null,
      activity_level: null,
      screen_time_hours: null,
      focus_minutes: null,
      mood_score: eveningCapture ? mood : null,
      mood_label: eveningCapture ? moodLabel(mood) : null,
      energy_level: energy,
      stress_level: eveningCapture ? stress : null,
      nutrition_notes: null,
      day_focus: null,
      reflection: null,
      source: 'quick_check_in',
      metadata: {
        ...metadata,
        capture_version: 'daily-capture-v4',
        captures: {
          morning: morningCapture,
          ...(eveningCapture ? { evening: eveningCapture } : {}),
        },
      },
      created_at: morningCapturedAt.toISOString(),
      updated_at: (eveningCapture ?? morningCapture).captured_at,
    };
  });
}

function buildBehavioralEvents(userId, scenario, dailyLogs, metadata) {
  return dailyLogs.flatMap((log, index) => {
    const date = new Date(`${log.entry_date}T12:00:00.000Z`);
    const captures = log.metadata?.captures;
    if (log.metadata?.capture_version === 'daily-capture-v4' && captures) {
      const evening = captures.evening;
      const morning = captures.morning;
      const signals = [];
      if (evening) {
        signals.push(
          ['mood', evening.mood, 'score_0_10', evening, 'evening'],
          ['stress', evening.stress_intensity, 'score_0_10', evening, 'evening'],
        );
      }
      if (morning) {
        signals.push(
          ['energy', morning.current_energy, 'score_0_10', morning, 'morning'],
          ['sleep', morning.sleep_hours, 'hours', morning, 'morning'],
        );
      }
      return signals.map(([eventType, value, unit, capture, captureKind]) => ({
        id: deterministicUuid(
          `demo-seed:capture-event:${log.id}:${eventType}`,
        ),
        user_id: userId,
        daily_log_id: log.id,
        event_type: eventType,
        value,
        unit,
        occurred_at: capture.captured_at,
        source: 'quick_check_in',
        metadata: {
          ...metadata,
          capture_version: 'daily-capture-v4',
          capture_kind: captureKind,
          entry_date: log.entry_date,
          capture_id: capture.capture_id,
          captured_at: capture.captured_at,
          ...(captureKind === 'morning'
            ? {
                day_shape: morning.day_shape,
                sleep_quality: morning.sleep_quality,
              }
            : {
                ...(evening.stress_source
                  ? { stress_source: evening.stress_source }
                  : {}),
                ...(evening.stress_controllability
                  ? { stress_controllability: evening.stress_controllability }
                  : {}),
              }),
        },
      }));
    }
    const base = [
      ['mood_score', log.mood_score, 'score'],
      ['energy_level', log.energy_level, 'score'],
      ['stress_level', log.stress_level, 'score'],
      ['focus_minutes', log.focus_minutes, 'minutes'],
      ['activity_level', log.activity_level, 'score'],
    ];
    return base.map(([eventType, value, unit], eventIndex) => ({
      id: deterministicUuid(`demo-seed:event:${log.id}:${eventType}`),
      user_id: userId,
      daily_log_id: log.id,
      event_type: eventType,
      value,
      unit,
      occurred_at: atHour(date, 9 + eventIndex * 2, 0),
      source: 'demo_seed',
      metadata: { ...metadata, entry_date: log.entry_date, day_index: index },
    }));
  });
}

function buildHabitLogs(userId, scenario, habits, now) {
  return habits.flatMap((habit, habitIndex) => {
    const pattern = scenario.habits[habitIndex][2];
    const cadence = habitCadenceProjection(scenario.habits[habitIndex][3]);
    return Array.from({ length: 21 }, (_, index) => {
      const date = addDays(now, index - 20);
      const weekday = isoWeekday(date);
      if (
        cadence.kind === 'weekdays' &&
        !cadence.scheduledWeekdays.includes(weekday)
      ) {
        return null;
      }
      const value = pattern[weekday - 1] ?? 0;
      if (value === 0) {
        return null;
      }
      const entryDate = dateOnly(date);
      const completed = value > 0;
      const timestamp = atHour(date, 19, habitIndex * 5);
      return {
        id: deterministicUuid(`demo-seed:habit-log:${habit.id}:${entryDate}`),
        user_id: userId,
        habit_id: habit.id,
        entry_date: entryDate,
        status: completed ? 'completed' : 'skipped',
        value: completed ? 1 : 0,
        notes: completed ? 'Demo completion' : 'Demo intentional skip',
        created_at: timestamp,
        updated_at: timestamp,
      };
    })
      .filter(Boolean);
  });
}

function buildStudentFocusEvidence(userId, taskRows, habitRows, now) {
  const openTasks = taskRows.filter((row) =>
    ['todo', 'in_progress'].includes(row.status),
  );
  if (openTasks.length < 2 || habitRows.length === 0) {
    throw new Error(
      'Student demo focus history requires two open tasks and a habit.',
    );
  }
  const timezone = 'Europe/Berlin';
  const today = localDateOnly(now, timezone);
  const historicalDates = [];
  for (let offset = -42; offset <= -1; offset += 1) {
    const localDate = addDateOnlyDays(today, offset);
    if (isoWeekday(new Date(`${localDate}T12:00:00.000Z`)) !== 7) {
      historicalDates.push(localDate);
    }
  }
  if (historicalDates.length < 36) {
    throw new Error(
      'Student Personal Learning history requires 36 distinct study days.',
    );
  }
  const sessions = [];
  const reflections = [];
  historicalDates.slice(-36).forEach((localDate, index) => {
    const preferredWindow = index % 2 === 0;
    const status =
      !preferredWindow && [9, 23, 33].includes(index)
        ? 'abandoned'
        : 'completed';
    const startedAt = zonedDateTime(
      localDate,
      preferredWindow ? '09:30' : '16:30',
      timezone,
    );
    const plannedMinutes = preferredWindow
      ? [45, 50, 60][index % 3]
      : [40, 45, 50][index % 3];
    const actualMinutes =
      status === 'abandoned'
        ? [22, 26, 28][index % 3]
        : preferredWindow
          ? [45, 50, 55][index % 3]
          : [38, 42, 46][index % 3];
    const endedAt = addMinutes(startedAt, actualMinutes);
    const sessionId = deterministicUuid(
      `demo-seed:focus:${userId}:rated:${localDate}`,
    );
    sessions.push({
      id: sessionId,
      user_id: userId,
      started_at: startedAt.toISOString(),
      ended_at: endedAt.toISOString(),
      planned_minutes: plannedMinutes,
      actual_minutes: actualMinutes,
      label: preferredWindow
        ? 'Morning course review'
        : 'Afternoon assignment work',
      distractions: status === 'abandoned' ? 3 : preferredWindow ? 0 : 1,
      social_media_warning: status === 'abandoned',
      notes:
        status === 'abandoned'
          ? 'Stopped when interruptions made the block unproductive.'
          : preferredWindow
            ? 'Made steady progress on one defined study goal.'
            : 'Completed a useful but more effortful study block.',
      status,
      task_id: index % 3 === 0 ? openTasks[index % openTasks.length].id : null,
      habit_id: null,
      metadata: {
        source: 'demo_seed_v3',
        scenario: 'student',
        entry_date: localDate,
      },
      created_at: startedAt.toISOString(),
      updated_at: endedAt.toISOString(),
    });
    const preferredRatingIndex = Math.floor(index / 2);
    reflections.push({
      focus_session_id: sessionId,
      user_id: userId,
      contract_version: 'focus-reflection-v1',
      focus_quality: preferredWindow
        ? preferredRatingIndex % 3 === 0
          ? 5
          : 4
        : status === 'abandoned'
          ? 2
          : 4,
      useful_progress: preferredWindow
        ? preferredRatingIndex % 4 === 0
          ? 5
          : 4
        : status === 'abandoned'
          ? 2
          : 3,
      obstacles:
        status === 'abandoned'
          ? [index % 2 === 0 ? 'distracted' : 'interrupted']
          : [],
    });
  });

  const activeStart = addMinutes(now, -8);
  sessions.push({
    id: deterministicUuid(`demo-seed:focus:${userId}:active`),
    user_id: userId,
    started_at: activeStart.toISOString(),
    ended_at: null,
    planned_minutes: 25,
    actual_minutes: null,
    label: 'History outline sprint',
    distractions: 0,
    social_media_warning: false,
    notes: null,
    status: 'active',
    task_id: openTasks[1].id,
    habit_id: null,
    metadata: {
      source: 'demo_seed_v3',
      scenario: 'student',
      entry_date: localDateOnly(activeStart, timezone),
    },
    created_at: activeStart.toISOString(),
    updated_at: activeStart.toISOString(),
  });
  return { sessions, reflections };
}

function habitCadenceProjection(config) {
  const kind = config?.kind ?? 'daily';
  if (kind === 'weekdays') {
    return {
      kind,
      frequency: 'daily',
      target: 1,
      scheduledWeekdays: [...config.scheduledWeekdays].sort(),
    };
  }
  if (kind === 'weekly_target') {
    return {
      kind,
      frequency: 'weekly',
      target: config.weeklyTarget,
      scheduledWeekdays: [],
    };
  }
  return {
    kind: 'daily',
    frequency: 'daily',
    target: 1,
    scheduledWeekdays: [],
  };
}

async function insertRows(table, rows) {
  if (rows.length === 0) {
    return;
  }
  await restRequest(
    table,
    {
      method: 'POST',
      body: JSON.stringify(rows),
      headers: { Prefer: 'return=minimal' },
    },
    `insert ${table}`,
  );
}

async function upsertRows(table, rows, conflictColumns) {
  if (rows.length === 0) {
    return;
  }
  await restRequest(
    `${table}?on_conflict=${encodeURIComponent(conflictColumns)}`,
    {
      method: 'POST',
      body: JSON.stringify(rows),
      headers: {
        Prefer: 'resolution=merge-duplicates,return=minimal',
      },
    },
    `upsert ${table}`,
  );
}

async function restRequest(path, options, description) {
  return request(
    `${supabaseUrl}/rest/v1/${path}`,
    {
      ...options,
      headers: {
        apikey: serviceRoleKey,
        Authorization: `Bearer ${serviceRoleKey}`,
        'Content-Type': 'application/json',
        ...(options.headers || {}),
      },
    },
    description,
  );
}

async function request(url, options, description) {
  const response = await fetch(url, options);
  if (!response.ok) {
    throw new Error(
      `Could not ${description}: ${response.status} ${await response.text()}`,
    );
  }

  const contentType = response.headers.get('content-type') || '';
  if (contentType.includes('application/json')) {
    return response.json();
  }
  return null;
}

function deterministicUuid(seed) {
  const bytes = crypto.createHash('sha256').update(seed).digest().subarray(0, 16);
  bytes[6] = (bytes[6] & 0x0f) | 0x50;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = bytes.toString('hex');
  return [
    hex.slice(0, 8),
    hex.slice(8, 12),
    hex.slice(12, 16),
    hex.slice(16, 20),
    hex.slice(20),
  ].join('-');
}

function addDays(baseDate, offset) {
  const date = new Date(baseDate);
  date.setUTCDate(date.getUTCDate() + offset);
  return date;
}

function addMinutes(baseDate, offset) {
  return new Date(baseDate.getTime() + offset * 60_000);
}

function startOfIsoWeek(date) {
  const copy = new Date(date);
  copy.setUTCHours(0, 0, 0, 0);
  copy.setUTCDate(copy.getUTCDate() - (isoWeekday(copy) - 1));
  return copy;
}

function isoWeekday(date) {
  return date.getUTCDay() || 7;
}

function dateOnly(date) {
  return date.toISOString().slice(0, 10);
}

function localDateOnly(date, timezone) {
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone: timezone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(date);
  const values = Object.fromEntries(
    parts
      .filter((part) => part.type !== 'literal')
      .map((part) => [part.type, part.value]),
  );
  return `${values.year}-${values.month}-${values.day}`;
}

function addDateOnlyDays(value, offset) {
  const date = new Date(`${value}T12:00:00.000Z`);
  date.setUTCDate(date.getUTCDate() + offset);
  return dateOnly(date);
}

function zonedDateTime(localDate, localClock, timezone) {
  const [year, month, day] = localDate.split('-').map(Number);
  const [hour, minute] = localClock.split(':').map(Number);
  const desiredAsUtc = Date.UTC(year, month - 1, day, hour, minute, 0, 0);
  let instant = desiredAsUtc;
  const formatter = new Intl.DateTimeFormat('en-US', {
    timeZone: timezone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    hourCycle: 'h23',
  });
  for (let attempt = 0; attempt < 3; attempt += 1) {
    const parts = Object.fromEntries(
      formatter
        .formatToParts(new Date(instant))
        .filter((part) => part.type !== 'literal')
        .map((part) => [part.type, part.value]),
    );
    const observedAsUtc = Date.UTC(
      Number(parts.year),
      Number(parts.month) - 1,
      Number(parts.day),
      Number(parts.hour),
      Number(parts.minute),
      Number(parts.second),
      0,
    );
    const correction = desiredAsUtc - observedAsUtc;
    instant += correction;
    if (correction === 0) {
      break;
    }
  }
  return new Date(instant);
}

function atHour(date, hour, minute) {
  const copy = new Date(date);
  copy.setUTCHours(hour, minute, 0, 0);
  return copy.toISOString();
}

function isoWeekKey(date) {
  const copy = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()));
  const day = copy.getUTCDay() || 7;
  copy.setUTCDate(copy.getUTCDate() + 4 - day);
  const yearStart = new Date(Date.UTC(copy.getUTCFullYear(), 0, 1));
  const week = Math.ceil(((copy - yearStart) / 86400000 + 1) / 7);
  return `${copy.getUTCFullYear()}-W${String(week).padStart(2, '0')}`;
}

function clampInt(value, min, max) {
  return Math.max(min, Math.min(max, Math.round(value)));
}

function clampNumber(value, min, max) {
  return Math.max(min, Math.min(max, value));
}

function moodLabel(score) {
  if (score >= 9) {
    return 'great';
  }
  if (score >= 7) {
    return 'good';
  }
  if (score >= 5) {
    return 'neutral';
  }
  if (score >= 3) {
    return 'low';
  }
  return 'very_low';
}

function stressIntensityLabel(score) {
  if (score >= 8) {
    return 'high';
  }
  if (score >= 5) {
    return 'medium';
  }
  return 'low';
}

function focusBand(minutes) {
  if (minutes <= 0) {
    return 'none';
  }
  if (minutes < 30) {
    return 'under_30_minutes';
  }
  if (minutes <= 60) {
    return '30_to_60_minutes';
  }
  if (minutes <= 120) {
    return '1_to_2_hours';
  }
  return 'over_2_hours';
}
