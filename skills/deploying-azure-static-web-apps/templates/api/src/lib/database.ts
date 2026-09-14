import sql from 'mssql';

// Module-level singleton — one pool per Functions host process.
// mssql v12+: the config object is NOT cloned by the library any more. Never mutate
// a config object after passing it to sql.connect() (undefined behaviour).
let pool: sql.ConnectionPool | null = null;

export async function getPool(): Promise<sql.ConnectionPool> {
  if (pool && pool.connected) return pool;

  const connectionString = process.env.SQL_CONNECTION_STRING;
  if (!connectionString) {
    // Callers check `process.env.SQL_CONNECTION_STRING` first and return a mock when
    // unset (see functions/getItems.ts). Reaching here without it is a programming error.
    throw new Error('SQL_CONNECTION_STRING environment variable is not set');
  }

  pool = await sql.connect(connectionString);
  return pool;
}

export async function query<T>(
  queryText: string,
  inputs: Array<{ name: string; value: string | number | boolean | null }> = []
): Promise<T[]> {
  const p = await getPool();
  const request = p.request();
  for (const { name, value } of inputs) {
    request.input(name, value);
  }
  const result = await request.query(queryText);
  return result.recordset as T[];
}
