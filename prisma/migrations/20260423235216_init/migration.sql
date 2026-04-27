-- CreateEnum
CREATE TYPE "Direction" AS ENUM ('LONG', 'SHORT');

-- CreateEnum
CREATE TYPE "Result" AS ENUM ('WIN', 'LOSS', 'BREAKEVEN');

-- CreateTable
CREATE TABLE "Trade" (
    "id" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "instrument" TEXT NOT NULL DEFAULT 'NAS100',
    "direction" "Direction" NOT NULL,
    "entryTime" TIMESTAMP(3) NOT NULL,
    "entryPrice" DOUBLE PRECISION NOT NULL,
    "stopPrice" DOUBLE PRECISION NOT NULL,
    "targetPrice" DOUBLE PRECISION NOT NULL,
    "exitPrice" DOUBLE PRECISION NOT NULL,
    "mfePrice" DOUBLE PRECISION,
    "rrPlanned" DOUBLE PRECISION NOT NULL,
    "rrAchieved" DOUBLE PRECISION NOT NULL,
    "rrPotential" DOUBLE PRECISION,
    "result" "Result" NOT NULL,
    "patternId" TEXT NOT NULL,
    "screenshotUrl" TEXT,
    "notes" TEXT,

    CONSTRAINT "Trade_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Pattern" (
    "id" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "description" TEXT,

    CONSTRAINT "Pattern_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "Pattern_name_key" ON "Pattern"("name");

-- AddForeignKey
ALTER TABLE "Trade" ADD CONSTRAINT "Trade_patternId_fkey" FOREIGN KEY ("patternId") REFERENCES "Pattern"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
