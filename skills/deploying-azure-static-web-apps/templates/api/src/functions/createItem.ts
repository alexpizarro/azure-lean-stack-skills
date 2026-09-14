import { app, HttpRequest, HttpResponseInit, InvocationContext } from '@azure/functions';
import { query } from '../lib/database';

interface Item {
  Id: number;
  Name: string;
  CreatedAt: string;
}

async function createItem(req: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> {
  try {
    const body = (await req.json()) as { name?: unknown };

    if (!body.name || typeof body.name !== 'string' || body.name.trim().length === 0) {
      return { status: 400, jsonBody: { error: 'name is required and must be a non-empty string' } };
    }

    // Mock when the DB isn't configured — the write is skipped, not faked as persisted.
    if (!process.env.SQL_CONNECTION_STRING) {
      context.warn('SQL_CONNECTION_STRING not set — skipping DB write');
      return { status: 201, jsonBody: { item: { Id: 0, Name: body.name.trim(), CreatedAt: new Date().toISOString() }, mock: true } };
    }

    const items = await query<Item>(
      'INSERT INTO dbo.Items (Name) OUTPUT INSERTED.Id, INSERTED.Name, INSERTED.CreatedAt VALUES (@name)',
      [{ name: 'name', value: body.name.trim() }]
    );

    return { status: 201, jsonBody: { item: items[0] } };
  } catch (err) {
    context.error('createItem failed:', err);
    return { status: 500, jsonBody: { error: 'Failed to create item' } };
  }
}

app.http('createItem', {
  methods: ['POST'],
  route: 'items',
  authLevel: 'anonymous',
  handler: createItem,
});
