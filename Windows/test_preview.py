import io,threading,time,unittest
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
from PIL import Image
from camera_remote import PreviewWorker,preview_frame_url
class PreviewTests(unittest.TestCase):
 def test_rejects_public_hosts_and_incomplete_links(self):
  for url in ('http://8.8.8.8:80/?key='+'a'*32,'https://192.168.1.2:80/?key='+'a'*32,'http://192.168.1.2:80/','http://example.com:80/?key='+'a'*32):
   with self.subTest(url=url),self.assertRaises(ValueError):preview_frame_url(url)
 def test_link_becomes_frame_request(self):
  self.assertEqual(preview_frame_url('http://192.168.1.2:1234/?key='+'a'*32),'http://192.168.1.2:1234/frame?key='+'a'*32)
 def _serve(self,mode):
  buffer=io.BytesIO();Image.new('RGB',(320,180),(30,60,90)).save(buffer,format='JPEG');body=buffer.getvalue()
  class Handler(BaseHTTPRequestHandler):
   def log_message(self,*args):pass
   def do_GET(self):
    if mode=='redirect':
     self.send_response(302);self.send_header('Location','http://8.8.8.8/');self.end_headers();return
    self.send_response(200);self.send_header('Content-Type','image/jpeg');self.end_headers();self.wfile.write(body if mode=='image' else b'not-an-image')
  server=ThreadingHTTPServer(('127.0.0.1',0),Handler);threading.Thread(target=server.serve_forever,daemon=True).start()
  worker=PreviewWorker(f'http://127.0.0.1:{server.server_port}/?key='+ 'b'*32)
  worker.thread.start()
  try:return worker.frames.get(timeout=4)
  finally:worker.stop();worker.thread.join(timeout=3);server.shutdown();server.server_close()
 def test_receives_actual_jpeg(self):
  kind,data=self._serve('image');self.assertEqual(kind,'frame');self.assertEqual(Image.open(io.BytesIO(data)).size,(320,180))
 def test_invalid_image_is_not_displayed(self):
  kind,_=self._serve('bad');self.assertEqual(kind,'status')
 def test_redirect_is_not_followed(self):
  kind,_=self._serve('redirect');self.assertEqual(kind,'status')
if __name__=='__main__':unittest.main()
