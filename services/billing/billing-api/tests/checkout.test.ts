import { expect, test } from 'bun:test';
import billing from '../src/index';

const checkout = (body: string) => billing.fetch(new Request('http://billing.test/api/v1/checkout-session', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body,
}));

test.each([
    ['unknown plan', '{"planId":"startre"}'],
    ['missing plan', '{}'],
    ['non-string plan', '{"planId":19}'],
    ['null body', 'null'],
    ['malformed JSON', '{'],
])('does not create a Growth session for %s', async (_label, body) => {
    const response = await checkout(body);
    expect(response.status).toBe(400);
    expect(await response.json()).toEqual({ error: 'An existing planId is required.' });
});

test.each([['starter', 19], ['growth', 49], ['scale', 149]])(
    'creates a session for the requested %s plan',
    async (planId, amount) => {
        const response = await checkout(JSON.stringify({ planId }));
        expect(response.status).toBe(200);
        const { data } = await response.json();
        expect(data).toMatchObject({ planId, amount, status: 'requires_payment_method' });
        expect(data.sessionId).toStartWith('cs_test_');
    },
);
