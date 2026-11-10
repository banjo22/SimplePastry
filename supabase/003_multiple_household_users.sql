-- Allows more than one authenticated user to access the same household.
-- Run once in the Supabase SQL editor after 001_schema.sql (and 002_reorder.sql if used).

alter table public.household_access drop constraint if exists household_access_pkey;
alter table public.household_access add primary key (user_id);

-- Example for adding another user:
-- insert into public.household_access (user_id)
-- values ('UUID-DES-ZWEITEN-BENUTZERS');
