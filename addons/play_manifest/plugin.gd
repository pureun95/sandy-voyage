@tool
extends EditorPlugin
## Android export tweak for Google Play.
## The game is portrait-locked (display/window/handheld/orientation), so Godot writes
## android:screenOrientation="portrait" on the activity. Google Play then treats
## android.hardware.screen.portrait as an implied *required* feature and limits device
## availability. Declaring the feature explicitly with required="false" keeps the portrait
## lock but removes the hardware requirement. Applied on every Android export (Gradle builds
## included), so it survives reinstalling the android/ build template.

var _export_plugin: EditorExportPlugin


func _enter_tree() -> void:
	_export_plugin = PlayManifestExport.new()
	add_export_plugin(_export_plugin)


func _exit_tree() -> void:
	remove_export_plugin(_export_plugin)
	_export_plugin = null


class PlayManifestExport extends EditorExportPlugin:
	const FEATURES := '<uses-feature android:name="android.hardware.screen.portrait" android:required="false" />'

	func _get_name() -> String:
		return "PlayManifest"

	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformAndroid

	func _get_android_manifest_element_contents(_platform: EditorExportPlatform, _debug: bool) -> String:
		return FEATURES
