import { app, HttpRequest, HttpResponseInit, InvocationContext } from '@azure/functions';
import { query } from '../lib/database';

interface Item {
  Id: number;
  Name: string;
  CreatedAt: string;
}

async function getItems(req: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> {
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
