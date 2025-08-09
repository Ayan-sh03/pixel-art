package;

import openfl.display.Bitmap;
import openfl.display.BitmapData;
import openfl.display.PixelSnapping;
import openfl.display.Sprite;
import openfl.display.StageAlign;
import openfl.display.StageScaleMode;
import openfl.events.Event;
import openfl.events.MouseEvent;
import openfl.events.KeyboardEvent;
import openfl.ui.Keyboard;
import openfl.geom.Rectangle;
#if sys
import sys.FileSystem;
import sys.io.File;
#end

class Main extends Sprite {
	var world:Sprite;
	var creaturePool:Array<Bitmap> = [];
	var activeCreatures:Map<Int, Bitmap> = new Map();

	var contentWidth:Float = 0;
	var creatureSize:Int = 16;
	var scaleFactor:Int = 20;
	var gap:Int = 30;
	var margin:Int = 20;

	var spacing:Float;

	public function new() {
		super();
		stage.align = StageAlign.TOP_LEFT;
		stage.scaleMode = StageScaleMode.NO_SCALE;

		world = new Sprite();
		addChild(world);

		spacing = (creatureSize * scaleFactor) + gap;

		// 1. Create a pool of reusable Bitmaps
		for (i in 0...10) { // 10 is enough for a smooth scroll
			var bmp = new Bitmap(null);
			bmp.scaleX = scaleFactor;
			bmp.scaleY = scaleFactor;
			bmp.smoothing = false;
			bmp.pixelSnapping = PixelSnapping.ALWAYS;
			bmp.visible = false; // start hidden
			creaturePool.push(bmp);
			world.addChild(bmp);
		}

		// 2. Add event listeners
		stage.addEventListener(Event.ENTER_FRAME, onEnterFrame);
		stage.addEventListener(MouseEvent.MOUSE_WHEEL, onWheel);
		stage.addEventListener(KeyboardEvent.KEY_DOWN, onKeyDown);

		// 3. Initial population
		updateVisibleCreatures();
	}

	function makeCreatureData(size:Int, density:Float, palette:Array<Int>):BitmapData {
		var bmpData = new BitmapData(size, size, false, 0x000000);

		var bodyPalette = filterBodyPalette(palette);
		var baseColor = bodyPalette[Std.int(Math.random() * bodyPalette.length)];
		var accentColor = bodyPalette[Std.int(Math.random() * bodyPalette.length)];
		// randomises
		// var eyeY = 4 + Std.int(Math.random() * (size - 8));
		var eyeY = 4;
		// Body: symmetric fill with slightly reduced density near the face
		for (x in 0...(size >> 1)) {
			for (y in 0...size) {
				var localDensity = density;
				if (y >= eyeY - 2 && y <= eyeY + 2)
					localDensity *= 0.55;

				if (Math.random() < localDensity) {
					var useAccent = Math.random() < 0.2;
					var color = useAccent ? accentColor : baseColor;
					bmpData.setPixel(x, y, color);
					bmpData.setPixel(size - 1 - x, y, color);
				}
			}
		}

		// Clear a small face area so eyes/mouth are visible
		carveFaceArea(bmpData, size, eyeY);

		addEyes(bmpData, size, eyeY);
		addMouth(bmpData, size);
		addHorns(bmpData, size, palette);

		return bmpData;
	}

	function filterBodyPalette(palette:Array<Int>):Array<Int> {
		var out = new Array<Int>();
		for (c in palette) {
			if (c != 0x000000 && c != 0xFFFFFF)
				out.push(c);
		}
		// Fallback if a palette was all dark/white
		if (out.length == 0)
			out = [0x6C5B7B, 0xC06C84, 0x355C7D];
		return out;
	}

	function carveFaceArea(bmpData:BitmapData, size:Int, eyeY:Int):Void {
		var bg = 0x000000;
		var cx = size >> 1;
		var mouthY = size - 4; // match where mouth will be placed

		// Larger face window: from eyes to mouth
		for (y in (eyeY - 1)...(mouthY + 2)) {
			for (x in (cx - 4)...(cx + 5)) {
				if (x >= 0 && x < size && y >= 0 && y < size) {
					bmpData.setPixel(x, y, bg);
				}
			}
		}
	}

	function addEyes(bmpData:BitmapData, size:Int, eyeY:Int):Void {
		var numEyes = 2; // 1..3
		// var numEyes = 1 + Std.int(Math.random() * 3); // 1..3
		var eyeColor = 0xFFFFFF;
		var pupilColor = 0x000000;
		var cx = size >> 1;
		var spacing = 3; // distance between eyes

		switch (numEyes) {
			case 1:
				bmpData.setPixel(cx, eyeY, eyeColor);
				bmpData.setPixel(cx, eyeY + 1, pupilColor);
			case 2:
				var l = cx - spacing;
				var r = cx + spacing;
				bmpData.setPixel(l, eyeY, eyeColor);
				bmpData.setPixel(r, eyeY, eyeColor);
				bmpData.setPixel(l, eyeY + 1, pupilColor);
				bmpData.setPixel(r, eyeY + 1, pupilColor);
			case 3:
				var l3 = cx - spacing;
				var r3 = cx + spacing;
				bmpData.setPixel(l3, eyeY, eyeColor);
				bmpData.setPixel(cx, eyeY, eyeColor);
				bmpData.setPixel(r3, eyeY, eyeColor);
				bmpData.setPixel(l3, eyeY + 1, pupilColor);
				bmpData.setPixel(cx, eyeY + 1, pupilColor);
				bmpData.setPixel(r3, eyeY + 1, pupilColor);
		}
	}

	function addMouth(bmpData:BitmapData, size:Int):Void {
		var mouthType = Std.int(Math.random() * 4);
		// var mouthType = 0;
		if (mouthType == 3)
			return;

		var mouthY = size - 4;
		var centerX = size >> 1;
		var mouthColor = 0xFFFFFF;

		switch (mouthType) {
			case 0: // happy

				for (dx in -3...4) {
					bmpData.setPixel(centerX + dx, mouthY, mouthColor);
				}
				// curve up at edges
				bmpData.setPixel(centerX - 4, mouthY - 1, mouthColor);
				bmpData.setPixel(centerX + 4, mouthY - 1, mouthColor);

			case 1: // big frown
				// mouth row
				for (dx in -3...4) {
					bmpData.setPixel(centerX + dx, mouthY + 1, mouthColor);
				}
				// curve down at edges
				bmpData.setPixel(centerX - 4, mouthY + 2, mouthColor);
				bmpData.setPixel(centerX + 4, mouthY + 2, mouthColor);
				// thicker top lip
				for (dx in -2...3) {
					bmpData.setPixel(centerX + dx, mouthY, mouthColor);
				}

			case 2: // open mouth
				// outer shape
				for (dx in -2...3) {
					bmpData.setPixel(centerX + dx, mouthY, mouthColor);
					bmpData.setPixel(centerX + dx, mouthY + 2, mouthColor);
				}
				bmpData.setPixel(centerX - 3, mouthY + 1, mouthColor);
				bmpData.setPixel(centerX + 3, mouthY + 1, mouthColor);
				// fill inside with a different color (tongue)
				var tongueColor = 0xFF4B4B; // bright red
				for (dx in -1...2) {
					bmpData.setPixel(centerX + dx, mouthY + 1, tongueColor);
				}
		}
	}

	function addHorns(bmpData:BitmapData, size:Int, palette:Array<Int>):Void {
		var hornType = Std.int(Math.random() * 4);
		if (hornType == 0)
			return;

		// var hornColor = palette[Std.int(Math.random() * palette.length)];
		var hornColor = 0xFFFF00; // bright yellow horns;
		var centerX = size >> 1;

		switch (hornType) {
			case 1:
				bmpData.setPixel(centerX - 3, 0, hornColor);
				bmpData.setPixel(centerX + 3, 0, hornColor);
			case 2:
				bmpData.setPixel(centerX - 2, 0, hornColor);
				bmpData.setPixel(centerX + 2, 0, hornColor);
				bmpData.setPixel(centerX - 2, 1, hornColor);
				bmpData.setPixel(centerX + 2, 1, hornColor);

			case 3: // new curved horns from your image
				// Left horn
				bmpData.setPixel(centerX - 2, 0, hornColor);
				bmpData.setPixel(centerX - 2, 1, hornColor);
				bmpData.setPixel(centerX - 3, 1, hornColor);
				bmpData.setPixel(centerX - 3, 2, hornColor);
				bmpData.setPixel(centerX - 4, 3, hornColor);

				// Right horn (mirrored)
				bmpData.setPixel(centerX + 2, 0, hornColor);
				bmpData.setPixel(centerX + 2, 1, hornColor);
				bmpData.setPixel(centerX + 3, 1, hornColor);
				bmpData.setPixel(centerX + 3, 2, hornColor);
				bmpData.setPixel(centerX + 4, 3, hornColor);
		}
	}

	function getRandomPalette():Array<Int> {
		var palettes = [
			[0x1D2B53, 0x7E2553, 0x008751, 0xAB5236, 0x5F574F], // Pico-8 dark
			[0xFF6B6B, 0x4ECDC4, 0x45B7D1, 0xF9CA24, 0x6C5CE7], // Soft pastels
			[0x2E1A47, 0x4B3F72, 0x6C5B7B, 0xC06C84, 0xF67280], // Muted purples
			[0x0D2B45, 0x203C56, 0x544E68, 0x8D697A, 0xD08159], // Earth tones
			[0x2D3748, 0x4A5568, 0x718096, 0xA0AEC0, 0xE2E8F0] // Grays
		];
		return palettes[Std.int(Math.random() * palettes.length)];
	}

	function onWheel(e:MouseEvent):Void {
		world.x -= e.delta * 40;
	}

	function onKeyDown(e:KeyboardEvent):Void {
		var step = 40;
		if (e.keyCode == Keyboard.RIGHT)
			world.x -= step;
		if (e.keyCode == Keyboard.LEFT)
			world.x += step;
	}

	function onResize(_:Event):Void {
		this.scrollRect = new Rectangle(0, 0, stage.stageWidth, stage.stageHeight);
		clampScroll();
	}

	function clampScroll():Void {
		var viewW = stage.stageWidth;
		var minX = Math.min(0.0, viewW - contentWidth); // negative
		if (world.x < minX)
			world.x = minX;
		if (world.x > 0)
			world.x = 0;
	}

	function onEnterFrame(e:Event):Void {
		updateVisibleCreatures();
	}

	function updateVisibleCreatures():Void {
		// Calculate which creature indices should be visible
		var viewLeft = -world.x;
		var viewRight = viewLeft + stage.stageWidth;
		var startIndex = Math.floor(viewLeft / spacing) - 1;
		var endIndex = Math.ceil(viewRight / spacing) + 1;

		// Deactivate creatures that are no longer visible
		for (index in activeCreatures.keys()) {
			if (index < startIndex || index > endIndex) {
				var bmp = activeCreatures.get(index);
				bmp.visible = false;
				activeCreatures.remove(index);
			}
		}

		// Activate creatures that should now be visible
		for (i in startIndex...endIndex) {
			if (!activeCreatures.exists(i)) {
				var bmp = findAvailableBitmap();
				if (bmp != null) {
					// Generate new art and position it
					var density = 0.2 + Math.random() * 0.6;
					var palette = getRandomPalette();
					bmp.bitmapData = makeCreatureData(creatureSize, density, palette);
					bmp.x = margin + i * spacing;
					bmp.y = 100;
					bmp.visible = true;
					activeCreatures.set(i, bmp);
				}
			}
		}
	}

	function findAvailableBitmap():Bitmap {
		for (bmp in creaturePool) {
			if (!bmp.visible)
				return bmp;
		}
		return null; // should not happen if pool is large enough
	}

	#if sys
	function saveCreaturePNG(bmpData:BitmapData, filePath:String):Void {
		var bytes = bmpData.encode(bmpData.rect, new PNGEncoderOptions());
		sys.io.File.saveBytes(filePath, bytes);
	}
	#end
}
