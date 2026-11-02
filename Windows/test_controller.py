import unittest, queue, asyncio
from unittest.mock import AsyncMock
from camera_remote import BluetoothWorker
class WorkerTests(unittest.TestCase):
 def setUp(self):
  self.w=BluetoothWorker.__new__(BluetoothWorker); self.w.events=queue.Queue(); self.w._notification_buffer=bytearray(); self.w.authorized=False; self.w.connected=False; self.w.client=None
 def test_fragmented_notifications(self):
  self.w._notification(None,bytearray(b'OK:AU')); self.assertFalse(self.w.authorized)
  self.w._notification(None,bytearray(b'TH\nREC:1\n')); self.assertTrue(self.w.authorized)
  self.assertIn(('message','REC:1'),list(self.w.events.queue))
 def test_auth_error_revokes(self):
  self.w.authorized=True; self.w._notification(None,bytearray(b'ERR:AUTH_REQUIRED\n')); self.assertFalse(self.w.authorized)
 def test_stale_disconnect(self):
  current=object();self.w.client=current;self.w.connected=True;self.w._disconnected(object());self.assertIs(self.w.client,current)
 def test_unauthorized_command_not_written(self):
  self.w.client=AsyncMock();self.w.client.is_connected=True
  asyncio.run(self.w.command('START'));self.w.client.write_gatt_char.assert_not_called()
 def test_authorized_command(self):
  self.w.client=AsyncMock();self.w.client.is_connected=True;self.w.authorized=True
  asyncio.run(self.w.command('STOP'));self.w.client.write_gatt_char.assert_awaited_once()
 def test_oversize_notification(self):
  self.w._notification(None,bytearray(b'x'*4097));self.assertEqual(len(self.w._notification_buffer),0)
if __name__=='__main__': unittest.main()
