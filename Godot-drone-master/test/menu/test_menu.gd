extends GutTest

const MenuScene := preload("res://scenes/Menu.tscn")

func test_menu_starts_hidden_and_uses_keyboard_text():
	var menu = autofree(MenuScene.instantiate())
	add_child(menu)
	await get_tree().process_frame

	assert_false(menu.visible)
	assert_eq(menu.controls_label.text, menu.KEYBOARD_TEXT)
