-- CreateEnum
CREATE TYPE "Source" AS ENUM ('SIMULATOR', 'REAL');

-- CreateEnum
CREATE TYPE "ExitReason" AS ENUM ('SL', 'TP', 'MANUAL');

-- AlterTable
ALTER TABLE "Trade"
  ADD COLUMN "source"          "Source"           NOT NULL DEFAULT 'SIMULATOR',
  ADD COLUMN "exitReason"      "ExitReason"        NOT NULL DEFAULT 'MANUAL',
  ADD COLUMN "sessionDate"     TIMESTAMP(3),
  ADD COLUMN "mfePoints"       DOUBLE PRECISION,
  ADD COLUMN "mae"             DOUBLE PRECISION,
  ADD COLUMN "maePoints"       DOUBLE PRECISION,
  ADD COLUMN "contractsQty"    INTEGER             NOT NULL DEFAULT 1,
  ADD COLUMN "commission"      DOUBLE PRECISION,
  ADD COLUMN "pnlGross"        DOUBLE PRECISION,
  ADD COLUMN "pnlNet"          DOUBLE PRECISION,
  ADD COLUMN "ratingSetup"     INTEGER,
  ADD COLUMN "ratingExecution" INTEGER,
  ADD COLUMN "followedPlan"    BOOLEAN             NOT NULL DEFAULT false,
  ADD COLUMN "tags"            TEXT;

-- AlterTable: make patternId optional
ALTER TABLE "Trade" ALTER COLUMN "patternId" DROP NOT NULL;
