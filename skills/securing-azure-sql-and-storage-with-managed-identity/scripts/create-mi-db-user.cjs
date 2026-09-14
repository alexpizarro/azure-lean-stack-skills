// create-mi-db-user.cjs
//
// Agent path: create the MI DB user WITHOUT interactive OAuth, provided the human has
// already `az login`'d AND is the SQL server's Entra admin. Mints an Entra access token
// for the SQL resource and connects with mssql access-token auth (a SQL login cannot
// create an external-provider user).
//
// Written as a .cjs FILE on purpose: an inline `node -e '...'` script's single-quotes
// collide with SQL string literals. A file has no quote collision.
//
// RUN FROM THE APP'S api/ DIR — `require('mssql')` resolves from THIS file's directory,
// not the shell cwd, so mssql must be resolvable from here (run it from api/, or copy it
// next to the app's node_modules, or use an absolute require path).
//
//   SQL_SERVER=<server>.database.windows.net \
//   SQL_DATABASE=<db> \
//   MI_NAME=<func-app-name> \
//   [GRANT_DDL=1]            # only if the app runs DDL at runtime; migrations use sqladmin
//   node scripts/create-mi-db-user.cjs
//
// Remember: SQL firewall blocks non-Azure IPs. Add a temp firewall rule for your IP
// before running, and delete it after (see the skill).

const { execSync } = require('node:child_process');
const sql = require('mssql');

const server = process.env.SQL_SERVER;
const database = process.env.SQL_DATABASE;
const miName = process.env.MI_NAME; // == Function App name == MI Entra display name
const grantDdl = process.env.GRANT_DDL === '1'; // least privilege by default

if (!server || !database || !miName) {
  console.error('Set SQL_SERVER, SQL_DATABASE and MI_NAME.');
  process.exit(1);
}

// Mint an Entra token for Azure SQL from the human's existing `az login` session.
const token = JSON.parse(
  execSync('az account get-access-token --resource https://database.windows.net/ -o json').toString(),
).accessToken;

const safeMi = miName.replace(/'/g, "''"); // escape for the SQL string literal

const setup = `
DECLARE @mi sysname = N'${safeMi}';
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = @mi)
  EXEC (N'CREATE USER ' + QUOTENAME(@mi) + N' FROM EXTERNAL PROVIDER;');
IF IS_ROLEMEMBER('db_datareader', @mi) = 0 EXEC (N'ALTER ROLE db_datareader ADD MEMBER ' + QUOTENAME(@mi) + N';');
IF IS_ROLEMEMBER('db_datawriter', @mi) = 0 EXEC (N'ALTER ROLE db_datawriter ADD MEMBER ' + QUOTENAME(@mi) + N';');
${grantDdl ? "IF IS_ROLEMEMBER('db_ddladmin',  @mi) = 0 EXEC (N'ALTER ROLE db_ddladmin  ADD MEMBER ' + QUOTENAME(@mi) + N';');" : ''}
`;

(async () => {
  await sql.connect({
    server,
    database,
    authentication: { type: 'azure-active-directory-access-token', options: { token } },
    options: { encrypt: true },
  });
  await sql.query(setup);
  console.log(`MI DB user ensured: ${miName} (db_datareader, db_datawriter${grantDdl ? ', db_ddladmin' : ''})`);
  await sql.close();
})().catch((err) => {
  console.error(err);
  process.exit(1);
});
