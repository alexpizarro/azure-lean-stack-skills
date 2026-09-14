import { app, HttpRequest, HttpResponseInit, InvocationContext } from '@azure/functions';
import { query } from '../lib/database';

interface Item {
  Id: number;
  Name: string;
  CreatedAt: string;
}

async function getItems(req: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> {
  // Mock when the DB isn't configured (local dev before the offline stack is up).
  if (!process.env.SQL_CONNECTION_STRING) {
    context.warn('SQL_CONNECTION_STRING not set — returning mock items');
    return { status: 200, jsonBody: { items: [{ Id: 1, Name: '[MOCK] Item', CreatedAt: new Date().toISOString() }] } };
  }
  try {
    const items = await query<Item>(
      'SELECT Id, Name, CreatedAt FROM dbo.Items ORDER BY CreatedAt DESC'
    );
    return { status: 200, jsonBody: { items } };
  } catch (err) {
    context.error('getItems failed:', err);
    return { status: 500, jsonBody: { error: 'Failed to fetch items' } };
  }
}

app.http('getItems', {
  methods: ['GET'],
  route: 'items',
  authLevel: 'anonymous',
  handler: getItems,
});
