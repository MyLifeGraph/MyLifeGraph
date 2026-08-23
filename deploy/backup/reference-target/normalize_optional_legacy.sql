\set ON_ERROR_STOP on

-- The source restore retains and verifies every optional legacy row. Schema
-- parity is migration-owned, so remove only the documented CamelCase
-- compatibility objects from both disposable targets after all recovery and
-- deletion-replay probes have completed.
begin;

drop table if exists public."FocusSession" cascade;
drop table if exists public."CoachMessage" cascade;
drop table if exists public."AIInsight" cascade;
drop table if exists public."ActivityLog" cascade;
drop table if exists public."DailyLog" cascade;
drop table if exists public."MemoryEntry" cascade;
drop table if exists public."MoodLog" cascade;
drop table if exists public."Notification" cascade;
drop table if exists public."ScheduleItem" cascade;
drop table if exists public."SleepLog" cascade;
drop table if exists public."Task" cascade;
drop table if exists public."Habit" cascade;
drop table if exists public."Goal" cascade;
drop table if exists public."User" cascade;

drop type if exists public."CoachRole" cascade;
drop type if exists public."GoalStatus" cascade;
drop type if exists public."HabitFrequency" cascade;
drop type if exists public."InsightCategory" cascade;
drop type if exists public."MemoryType" cascade;
drop type if exists public."Mood" cascade;
drop type if exists public."NotificationType" cascade;
drop type if exists public."Priority" cascade;
drop type if exists public."TaskStatus" cascade;

commit;
