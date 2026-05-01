-- DropForeignKey
ALTER TABLE "Trade" DROP CONSTRAINT "Trade_patternId_fkey";

-- AlterTable
ALTER TABLE "Trade" ADD COLUMN     "capitalInicial" DOUBLE PRECISION,
ADD COLUMN     "lotSize" DOUBLE PRECISION,
ADD COLUMN     "riskPct" DOUBLE PRECISION,
ADD COLUMN     "slPoints" DOUBLE PRECISION,
ADD COLUMN     "tpPoints" DOUBLE PRECISION;

-- AddForeignKey
ALTER TABLE "Trade" ADD CONSTRAINT "Trade_patternId_fkey" FOREIGN KEY ("patternId") REFERENCES "Pattern"("id") ON DELETE SET NULL ON UPDATE CASCADE;
