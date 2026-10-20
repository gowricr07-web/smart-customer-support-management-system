// Loads seed.cypher (same dataset as DA3 file 01) into Neo4j: npm run seed
const fs = require("fs");
const path = require("path");
const { driver } = require("./db");

(async () => {
  const text = fs.readFileSync(path.join(__dirname, "seed.cypher"), "utf8")
    .split("\n").filter(l => !l.trim().startsWith("//")).join("\n");
  const statements = text.split(/;\s*\n/).map(s => s.trim()).filter(Boolean);
  const session = driver.session();
  try {
    for (const [i, st] of statements.entries()) {
      await session.run(st);
      process.stdout.write(`\rExecuted ${i + 1}/${statements.length}`);
    }
    console.log("\nSeed complete.");
  } catch (e) {
    console.error("\nSeed failed:", e.message);
    process.exitCode = 1;
  } finally {
    await session.close();
    await driver.close();
  }
})();
