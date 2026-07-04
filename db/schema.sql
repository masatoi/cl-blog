CREATE TABLE "learn_submission" (
    "id" BIGSERIAL NOT NULL PRIMARY KEY,
    "user_id" UUID NOT NULL,
    "notebook_id" VARCHAR(64) NOT NULL,
    "cell_id" VARCHAR(64) NOT NULL,
    "code" TEXT NOT NULL,
    "status" VARCHAR(16) NOT NULL,
    "created_at" TIMESTAMPTZ,
    "updated_at" TIMESTAMPTZ
);
CREATE INDEX "key_learn_submission_user_id_notebook_id_cell_id" ON "learn_submission" ("user_id", "notebook_id", "cell_id");

CREATE TABLE "learn_cell_code" (
    "id" BIGSERIAL NOT NULL PRIMARY KEY,
    "user_id" UUID NOT NULL,
    "notebook_id" VARCHAR(64) NOT NULL,
    "cell_id" VARCHAR(64) NOT NULL,
    "code" TEXT NOT NULL,
    "created_at" TIMESTAMPTZ,
    "updated_at" TIMESTAMPTZ
);
CREATE UNIQUE INDEX "unique_learn_cell_code_user_id_notebook_id_cell_id" ON "learn_cell_code" ("user_id", "notebook_id", "cell_id");
CREATE INDEX "key_learn_cell_code_user_id_notebook_id" ON "learn_cell_code" ("user_id", "notebook_id");

CREATE TABLE "learn_progress" (
    "id" BIGSERIAL NOT NULL PRIMARY KEY,
    "user_id" UUID NOT NULL,
    "notebook_id" VARCHAR(64) NOT NULL,
    "cell_id" VARCHAR(64) NOT NULL,
    "passed_at" TIMESTAMPTZ NOT NULL,
    "created_at" TIMESTAMPTZ,
    "updated_at" TIMESTAMPTZ
);
CREATE UNIQUE INDEX "unique_learn_progress_user_id_notebook_id_cell_id" ON "learn_progress" ("user_id", "notebook_id", "cell_id");
CREATE INDEX "key_learn_progress_user_id_notebook_id" ON "learn_progress" ("user_id", "notebook_id");

CREATE TABLE "novel_state" (
    "id" BIGSERIAL NOT NULL PRIMARY KEY,
    "user_id" UUID NOT NULL,
    "notebook_id" VARCHAR(64) NOT NULL,
    "flags" TEXT NOT NULL,
    "scene_index" INTEGER NOT NULL,
    "created_at" TIMESTAMPTZ,
    "updated_at" TIMESTAMPTZ
);
CREATE INDEX "key_novel_state_user_id_notebook_id" ON "novel_state" ("user_id", "notebook_id");
CREATE UNIQUE INDEX "unique_novel_state_user_id_notebook_id" ON "novel_state" ("user_id", "notebook_id");

CREATE TABLE "users" (
    "id" UUID NOT NULL PRIMARY KEY,
    "email" VARCHAR(255) NOT NULL,
    "handle" VARCHAR(64) NOT NULL,
    "password_hash" VARCHAR(255),
    "password_salt" VARCHAR(255),
    "display_name" VARCHAR(255) NOT NULL,
    "role" VARCHAR(64) NOT NULL,
    "language" VARCHAR(16),
    "timezone" VARCHAR(64),
    "provider" VARCHAR(16),
    "provider_uid" VARCHAR(64),
    "created_at" TIMESTAMPTZ,
    "updated_at" TIMESTAMPTZ
);
CREATE UNIQUE INDEX "unique_users_email" ON "users" ("email");
CREATE UNIQUE INDEX "unique_users_handle" ON "users" ("handle");

CREATE TABLE "course" (
    "id" UUID NOT NULL PRIMARY KEY,
    "slug" VARCHAR(255) NOT NULL,
    "title" VARCHAR(255) NOT NULL,
    "summary" VARCHAR(500),
    "status" VARCHAR(32) NOT NULL,
    "visibility" VARCHAR(32) NOT NULL,
    "published_at" TIMESTAMPTZ,
    "author_id" UUID NOT NULL,
    "created_at" TIMESTAMPTZ,
    "updated_at" TIMESTAMPTZ
);
CREATE UNIQUE INDEX "unique_course_author_id_slug" ON "course" ("author_id", "slug");
CREATE INDEX "key_course_status_created_at" ON "course" ("status", "created_at");
CREATE INDEX "key_course_author_id_created_at" ON "course" ("author_id", "created_at");
CREATE INDEX "key_course_visibility_status" ON "course" ("visibility", "status");

CREATE TABLE "notebook" (
    "id" UUID NOT NULL PRIMARY KEY,
    "slug" VARCHAR(255) NOT NULL,
    "title" VARCHAR(255) NOT NULL,
    "summary" VARCHAR(500),
    "body_md" TEXT NOT NULL,
    "cells" JSONB NOT NULL,
    "status" VARCHAR(32) NOT NULL,
    "visibility" VARCHAR(32) NOT NULL,
    "published_at" TIMESTAMPTZ,
    "author_id" UUID NOT NULL,
    "created_at" TIMESTAMPTZ,
    "updated_at" TIMESTAMPTZ
);
CREATE UNIQUE INDEX "unique_notebook_author_id_slug" ON "notebook" ("author_id", "slug");
CREATE INDEX "key_notebook_status_created_at" ON "notebook" ("status", "created_at");
CREATE INDEX "key_notebook_author_id_created_at" ON "notebook" ("author_id", "created_at");
CREATE INDEX "key_notebook_visibility_status" ON "notebook" ("visibility", "status");

CREATE TABLE "course_notebook" (
    "id" BIGSERIAL NOT NULL PRIMARY KEY,
    "course_id" UUID NOT NULL,
    "notebook_id" UUID NOT NULL,
    "position" INTEGER NOT NULL,
    "created_at" TIMESTAMPTZ,
    "updated_at" TIMESTAMPTZ
);
CREATE UNIQUE INDEX "unique_course_notebook_course_id_notebook_id" ON "course_notebook" ("course_id", "notebook_id");
CREATE INDEX "key_course_notebook_course_id_position" ON "course_notebook" ("course_id", "position");

-- Lack DBI session store backing table (see web/server.lisp make-session-store).
-- Not a Mito model; managed by ensure-sessions-table! at server start.
CREATE TABLE IF NOT EXISTS "sessions" (
    "id" VARCHAR(255) NOT NULL PRIMARY KEY,
    "session_data" TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS "schema_migrations" (
    "version" BIGINT PRIMARY KEY,
    "applied_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "dirty" BOOLEAN NOT NULL DEFAULT false
);
