CREATE TABLE "users" (
    "id" UUID NOT NULL PRIMARY KEY,
    "email" VARCHAR(255) NOT NULL,
    "password_hash" VARCHAR(255) NOT NULL,
    "password_salt" VARCHAR(255) NOT NULL,
    "display_name" VARCHAR(255) NOT NULL,
    "role" VARCHAR(64) NOT NULL,
    "language" VARCHAR(16),
    "timezone" VARCHAR(64),
    "created_at" TIMESTAMPTZ,
    "updated_at" TIMESTAMPTZ
);
CREATE UNIQUE INDEX "unique_users_email" ON "users" ("email");

CREATE TABLE "post" (
    "id" UUID NOT NULL PRIMARY KEY,
    "title" VARCHAR(255) NOT NULL,
    "slug" VARCHAR(255) NOT NULL,
    "body" TEXT NOT NULL,
    "excerpt" VARCHAR(500),
    "status" VARCHAR(32) NOT NULL,
    "published_at" TIMESTAMPTZ,
    "author_id" UUID,
    "created_at" TIMESTAMPTZ,
    "updated_at" TIMESTAMPTZ
);
CREATE UNIQUE INDEX "unique_post_slug" ON "post" ("slug");
CREATE INDEX "key_post_status_created_at" ON "post" ("status", "created_at");

CREATE TABLE IF NOT EXISTS "schema_migrations" (
    "version" BIGINT PRIMARY KEY,
    "applied_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "dirty" BOOLEAN NOT NULL DEFAULT false
);
