class_name ThumbLoader
extends Node
## Small postcard textures made on demand from album images, so a 300-postcard album never
## holds the full-size originals. A request starts a threaded load; once loaded (at most one
## per frame) the image is shrunk to `THUMB_PX`, kept as an ImageTexture and the original is
## dropped. Least recently used thumbnails beyond `MAX_THUMBS` are released.
## Owned by the App autoload (App.thumbs).

signal thumb_ready(path: String)

const THUMB_PX := 256
const MAX_THUMBS := 48

var _thumbs := {}     # path -> ImageTexture
var _order: Array[String] = []   # LRU, most recent last
var _pending := {}    # path -> true (threaded load running)


## Cached thumbnail, or null (a load starts; `thumb_ready` fires when it is available).
func get_thumb(path: String) -> Texture2D:
	if path == "":
		return null
	if _thumbs.has(path):
		_order.erase(path)
		_order.append(path)
		return _thumbs[path]
	if not _pending.has(path) and ResourceLoader.exists(path):
		if ResourceLoader.load_threaded_request(path, "Texture2D") == OK:
			_pending[path] = true
			set_process(true)
	return null


func cached_count() -> int:
	return _thumbs.size()


func _ready() -> void:
	set_process(false)


func _process(_delta: float) -> void:
	for path in _pending.keys():
		var st := ResourceLoader.load_threaded_get_status(path)
		if st == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			continue
		_pending.erase(path)
		if st == ResourceLoader.THREAD_LOAD_LOADED:
			var tex := ResourceLoader.load_threaded_get(path) as Texture2D
			if tex != null:
				_store(path, tex)
		break  # at most one finished image per frame
	if _pending.is_empty():
		set_process(false)


func _store(path: String, tex: Texture2D) -> void:
	var img := tex.get_image()
	if img == null or img.is_empty():
		return
	if img.is_compressed():
		img.decompress()
	var w := img.get_width()
	var h := img.get_height()
	if maxi(w, h) > THUMB_PX:
		var k := float(THUMB_PX) / maxi(w, h)
		img.resize(maxi(1, roundi(w * k)), maxi(1, roundi(h * k)), Image.INTERPOLATE_LANCZOS)
	_thumbs[path] = ImageTexture.create_from_image(img)
	_order.append(path)
	while _order.size() > MAX_THUMBS:
		_thumbs.erase(_order.pop_front())
	thumb_ready.emit(path)
