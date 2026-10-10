#!/bin/sh
# Customises Neko's web page (the page friends open). Runs once when the neko
# container starts (see client-patch.conf). Each change is skipped safely if a
# future Neko release no longer contains the code it looks for.
#
# 1. Instant control handover: when a friend clicks "Take control" while another
#    friend is driving, the driver's page hands control over automatically
#    (stock Neko only shows "X is requesting the controls"). Admin pages are left
#    alone, so nobody takes control from you without asking, and "Lock controls"
#    still blocks friends entirely.
# 2. Custom look: links custom/ui.css (client-patch/www/ui.css on the Mac).
# 3. Shared pointer: loads custom/cursor.js (draws the driver's pointer for
#    everyone else; see NEKO_CAPTURE_VIDEO_SHOW_POINTER in docker-compose.yml).
# 4. Full screen: loads custom/fullscreen.js (one Esc press exits in every browser).
# 5. Quiet control changes: no chat sound when someone takes/releases control
#    (real chat messages still play it).

WWW=/var/www

# patch_js NAME SED_EXPRESSION: apply a small change to Neko's page code (both copies), once.
# The expression leaves a /*NAME*/ marker so it's never applied twice.
patch_js() {
	for f in "$WWW"/js/app.*.js "$WWW"/js/app-legacy.*.js; do
		[ -f "$f" ] || continue
		if grep -qF "/*$1*/" "$f"; then
			echo "$f: $1 already patched"
			continue
		fi
		sed -i "$2" "$f"
		if grep -qF "/*$1*/" "$f"; then
			echo "$f: $1 patched"
		else
			echo "$f: $1 pattern not found, left unchanged (stock behaviour)"
		fi
	done
}

# 1. instant handover: a friend's page gives control to whoever asks (admin pages don't)
patch_js auto-handover 's#\([A-Za-z_$][A-Za-z0-9_$]*\)&&!\1\.ignored&&this\.\$vue\.\$notify({group:"neko",type:"info",title:this\.\$vue\.\$t("notifications\.controls_requesting"#/*auto-handover*/\1\&\&!\1.ignored\&\&!this.$accessor.user.admin\&\&this.$accessor.remote.give(\1),&#'

# 5. quiet control changes: no chat sound for "took/released the controls" (type "event") entries
patch_js quiet-events 's#(\([A-Za-z_$][A-Za-z0-9_$]*\),\([A-Za-z_$][A-Za-z0-9_$]*\)){\([A-Za-z_$][A-Za-z0-9_$]*\)\.settings\.chat_sound&&new Audio("chat\.mp3")#(\1,\2){/*quiet-events*/\3.settings.chat_sound\&\&"event"!==\2.type\&\&new Audio("chat.mp3")#'

# insert a tag before </head> unless it's already there
inject() {
	if grep -qF "$1" "$WWW/index.html"; then
		echo "index.html: $1 already linked"
	elif grep -qF '</head>' "$WWW/index.html"; then
		sed -i "s#</head>#$2</head>#" "$WWW/index.html"
		echo "index.html: $1 linked"
	else
		echo "index.html: </head> not found, $1 not linked (stock page)"
	fi
}
inject custom/ui.css '<link href="custom/ui.css" rel="stylesheet">'
inject custom/cursor.js '<script src="custom/cursor.js"></script>'
inject custom/fullscreen.js '<script src="custom/fullscreen.js"></script>'
