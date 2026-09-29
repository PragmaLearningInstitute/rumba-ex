-- RUMBA.EX web app uses the public PLI account session (users_public/auth_sessions),
-- not Directus admin accounts. This migration attaches student profiles to the
-- same public account that is already logged in on pragmalearninginstitute.com.

CREATE TABLE IF NOT EXISTS rumba_ex_profiles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_created uuid REFERENCES directus_users(id) ON DELETE SET NULL,
  date_created timestamptz NOT NULL DEFAULT now(),
  date_updated timestamptz NOT NULL DEFAULT now(),
  student_name varchar(100) NOT NULL,
  age integer NOT NULL,
  blockers jsonb NOT NULL DEFAULT '[]'::jsonb,
  exercise_target integer NOT NULL DEFAULT 3,
  temperature double precision NOT NULL DEFAULT 0.8
);

ALTER TABLE rumba_ex_profiles
  ADD COLUMN IF NOT EXISTS public_user_id uuid REFERENCES users_public(id) ON DELETE CASCADE;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'rumba_ex_profiles'::regclass
      AND conname = 'rumba_ex_profiles_age_check'
  ) THEN
    ALTER TABLE rumba_ex_profiles
      ADD CONSTRAINT rumba_ex_profiles_age_check CHECK (age BETWEEN 6 AND 14);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'rumba_ex_profiles'::regclass
      AND conname = 'rumba_ex_profiles_exercise_target_check'
  ) THEN
    ALTER TABLE rumba_ex_profiles
      ADD CONSTRAINT rumba_ex_profiles_exercise_target_check CHECK (exercise_target BETWEEN 1 AND 5);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'rumba_ex_profiles'::regclass
      AND conname = 'rumba_ex_profiles_temperature_check'
  ) THEN
    ALTER TABLE rumba_ex_profiles
      ADD CONSTRAINT rumba_ex_profiles_temperature_check CHECK (temperature BETWEEN 0.1 AND 3.0);
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_rumba_ex_profiles_public_user
ON rumba_ex_profiles (public_user_id, date_updated DESC, date_created DESC);

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_name = 'rumba_ex_profiles'
      AND column_name = 'user_created'
      AND is_nullable = 'NO'
  ) THEN
    ALTER TABLE rumba_ex_profiles ALTER COLUMN user_created DROP NOT NULL;
  END IF;
END $$;

INSERT INTO directus_collections (
  collection,
  icon,
  note,
  display_template,
  hidden,
  singleton,
  translations,
  archive_field,
  archive_app_filter,
  archive_value,
  unarchive_value,
  sort_field,
  accountability,
  color,
  item_duplication_fields,
  sort,
  "group",
  collapse,
  preview_url,
  versioning
)
VALUES (
  'rumba_ex_profiles',
  'psychology',
  'Student profiles for the RUMBA.EX web app. Ownership is enforced through users_public and the PLI session cookie.',
  '{{ student_name }} · {{ age }} ans',
  false,
  false,
  null,
  null,
  true,
  null,
  null,
  null,
  'all',
  null,
  null,
  352,
  null,
  'open',
  null,
  false
)
ON CONFLICT (collection) DO UPDATE SET
  icon = EXCLUDED.icon,
  note = EXCLUDED.note,
  display_template = EXCLUDED.display_template,
  hidden = EXCLUDED.hidden,
  accountability = EXCLUDED.accountability,
  sort = EXCLUDED.sort,
  collapse = EXCLUDED.collapse,
  versioning = EXCLUDED.versioning;

UPDATE directus_fields
SET required = false
WHERE collection = 'rumba_ex_profiles'
  AND field = 'user_created';

INSERT INTO directus_relations (
  many_collection,
  many_field,
  one_collection,
  one_field,
  one_collection_field,
  one_allowed_collections,
  junction_field,
  sort_field,
  one_deselect_action
)
SELECT 'rumba_ex_profiles', 'public_user_id', 'users_public', null, null, null, null, null, 'delete'
WHERE NOT EXISTS (
  SELECT 1 FROM directus_relations
  WHERE many_collection = 'rumba_ex_profiles'
    AND many_field = 'public_user_id'
);

INSERT INTO directus_fields (
  collection,
  field,
  special,
  interface,
  options,
  display,
  display_options,
  readonly,
  hidden,
  sort,
  width,
  note,
  conditions,
  required,
  "group",
  validation,
  validation_message
)
VALUES (
  'rumba_ex_profiles',
  'public_user_id',
  'm2o',
  'select-dropdown-m2o',
  null,
  'related-values',
  '{"template":"{{ email }}"}'::json,
  true,
  false,
  15,
  'full',
  'Public PLI account owner used by the web app session cookie.',
  null,
  false,
  null,
  null,
  null
)
ON CONFLICT (collection, field) DO UPDATE SET
  special = EXCLUDED.special,
  interface = EXCLUDED.interface,
  display = EXCLUDED.display,
  display_options = EXCLUDED.display_options,
  readonly = EXCLUDED.readonly,
  hidden = EXCLUDED.hidden,
  sort = EXCLUDED.sort,
  width = EXCLUDED.width,
  note = EXCLUDED.note;

COMMENT ON COLUMN rumba_ex_profiles.public_user_id IS
  'Owner in users_public for RUMBA.EX web profiles. Enforced by the site BFF through pli_session.';
