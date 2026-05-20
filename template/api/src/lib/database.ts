import sql from 'mssql';

let pool: sql.ConnectionPool | null = null;

async function getPool(): Promise<sql.ConnectionPool> {
  if (pool && pool.connected) return pool;

  const connectionString = process.env.SQL_CONNECTION_STRING;
  if (!connectionString) {
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
