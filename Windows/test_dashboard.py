import unittest
from unittest.mock import patch
from camera_remote import CameraRemoteApp
class DashboardTests(unittest.TestCase):
 def setUp(self):
  self.app=CameraRemoteApp(); self.app.withdraw()
 def tearDown(self): self.app._close()
 def test_only_confirmed_recording_starts_timer(self):
  self.app._handle_status('OK:STARTING');self.assertFalse(self.app.recording_active)
  self.app._handle_status('REC:1');started=self.app.recording_since
  self.app._handle_status('REC:1');self.assertEqual(started,self.app.recording_since)
  self.app._handle_status('REC:0');self.assertFalse(self.app.recording_active)
 def test_photos_failure_never_claims_gallery_saved(self):
  self.app._handle_status('SAVE:PHOTOS_FAILED');self.assertIn('Files copy is safe',self.app.save_var.get())
  self.app._handle_status('SAVE:PHOTOS_OK');self.assertIn('SAVED TO PHOTOS',self.app.save_var.get())
 def test_status_refresh_keeps_mode_and_camera(self):
  self.app._handle_status('STATUS:READY=1;REC=1;MODE=4K60;CAM=FRONT')
  self.assertEqual(self.app.mode_var.get(),'4K60');self.assertEqual(self.app.camera_var.get(),'FRONT');self.assertTrue(self.app.recording_active)
if __name__=='__main__':unittest.main()
