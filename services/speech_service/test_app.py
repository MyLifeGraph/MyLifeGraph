import unittest
from unittest.mock import AsyncMock, patch

import httpx

import app
from install import patched_caddy, ADDITION


class InstallerTest(unittest.TestCase):
    def test_caddy_change_is_only_additive_and_refuses_repeat(self):
        before = 'example.com {\n\treverse_proxy 127.0.0.1:8000 {\n\t}\n}\n'
        after = patched_caddy(before)
        self.assertEqual(after.replace(ADDITION, ''), before)
        with self.assertRaises(ValueError):
            patched_caddy(after)
        with self.assertRaises(ValueError):
            patched_caddy('unexpected configuration')


class SpeechTest(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        app._starts.clear()
        self.client = httpx.AsyncClient(transport=httpx.ASGITransport(app=app.app),
                                        base_url='http://speech')

    async def asyncTearDown(self):
        await self.client.aclose()

    async def test_missing_auth_never_runs_model(self):
        with patch.object(app, 'recognize', new_callable=AsyncMock) as recognize:
            response = await self.client.post('/v1/speech/transcribe', content=b'00')
            self.assertEqual(response.status_code, 401)
            recognize.assert_not_called()

    async def test_limits_and_success(self):
        with patch.object(app, 'authorize', new_callable=AsyncMock), \
             patch.object(app, 'recognize', new_callable=AsyncMock, return_value='Hallo') as recognize:
            headers = {'Content-Type': 'application/octet-stream'}
            response = await self.client.post('/v1/speech/transcribe',
                headers=headers, content=b'\x00' * (app.MAX_BYTES + 2))
            self.assertEqual(response.status_code, 413)
            recognize.assert_not_called()
            response = await self.client.post('/v1/speech/transcribe',
                headers=headers, content=b'\x00' * 3200)
            self.assertEqual(response.json(), {'text': 'Hallo'})

    async def test_busy_never_runs_model(self):
        async with app._lock:
            response = await self.client.post('/v1/speech/transcribe')
        self.assertEqual(response.status_code, 429)

    async def test_auth_failure_stays_closed(self):
        response = httpx.Response(423)
        with patch.object(app.httpx, 'AsyncClient', return_value=httpx.AsyncClient(
                transport=httpx.MockTransport(lambda request: response))):
            with patch.object(app, 'recognize', new_callable=AsyncMock) as recognize:
                result = await self.client.post('/dev/v1/speech/transcribe',
                    headers={'Authorization': 'Bearer invalid'})
                self.assertEqual(result.status_code, 423)
                recognize.assert_not_called()


if __name__ == '__main__':
    unittest.main()
