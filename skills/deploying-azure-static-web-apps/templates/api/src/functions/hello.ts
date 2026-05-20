import { app, HttpRequest, HttpResponseInit, InvocationContext } from '@azure/functions';

async function hello(req: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> {
  context.log('hello function triggered');
  return {
    status: 200,
    jsonBody: {
      message: 'Hello from Azure Functions!',
      timestamp: new Date().toISOString(),
      environment: process.env.AZURE_FUNCTIONS_ENVIRONMENT ?? 'Development',
    },
  };
}

app.http('hello', {
  methods: ['GET'],
  authLevel: 'anonymous',
  handler: hello,
});
