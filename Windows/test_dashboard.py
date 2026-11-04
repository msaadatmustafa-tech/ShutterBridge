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
 def test_quality_selection_survives_status_poll(self):
  self.app.mode_var.set('4K60');self.app.mode_dirty=True
  self.app._handle_status('STATUS:READY=1;REC=0;BUSY=0;MODE=1080P30;CAM=BACK;CAPS=4K60,1080P30;WIDTH=1920;HEIGHT=1080;FPS=30.00')
  self.assertEqual(self.app.mode_var.get(),'4K60');self.assertIn('1080P30',self.app.confirmed_quality.get())
 def test_capabilities_remove_unsupported_mode(self):
  self.app.mode_var.set('4K60');self.app.mode_dirty=True
  self.app._handle_status('STATUS:READY=1;REC=0;MODE=1080P30;CAM=FRONT;CAPS=1080P30,720P30')
  self.assertEqual(self.app.mode_var.get(),'1080P30');self.assertNotIn('4K60',self.app.mode_combo.cget('values'))
 def test_saving_blocks_quality_and_start(self):
  self.app.authorized=True;self.app.connection_ok=True
  self.app._handle_status('STATUS:READY=1;REC=0;BUSY=1;MODE=4K60;CAM=BACK')
  self.assertEqual(self.app.start_btn.cget('state'),'disabled');self.assertEqual(self.app.apply_btn.cget('state'),'disabled')
  self.assertEqual(self.app.live_apply_btn.cget('state'),'disabled');self.assertIn('SAVING',self.app.recording_var.get())
 def test_clip_metadata_is_separate_from_selection(self):
  self.app._handle_status('CLIP:3840x2160@59.94fps')
  self.assertIn('3840x2160@59.94fps',self.app.clip_quality.get())
 def test_mode_ack_clears_pending_selection(self):
  self.app.mode_dirty=True;self.app._handle_status('OK:MODE:4K30')
  self.assertFalse(self.app.mode_dirty);self.assertEqual(self.app.mode_var.get(),'4K30')
if __name__=='__main__':unittest.main()
