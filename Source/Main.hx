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
import openfl.display.PNGEncoderOptions;
#end

enum BodyType {
	Blob;      // Round, even width
	Tall;      // Narrow, elongated  
	Wide;      // Short, broad
	Pear;      // Narrow top, wide bottom
	Inverted;  // Wide top, narrow bottom
	Hourglass; // Wide-narrow-wide
}

class Main extends Sprite {
	var world:Sprite;
    var background:Sprite;
    var bgTiles:Array<Bitmap> = [];
    var bgTileBD:BitmapData;
    var bgTileSize:Int = 128;
    var bgParallax:Float = 0.2;
    var bgDrift:Float = 0.0;
    var bgBaseColors:Array<Int> = [];
    var bgAccentColor:Int = 0xFFFFFF;
	var creaturePool:Array<Bitmap> = [];
	var activeCreatures:Map<Int, Bitmap> = new Map();
	var contentWidth:Float = 0;
	var creatureSize:Int = 16;
	var scaleFactor:Int = 20;
	var gap:Int = 30;
	var margin:Int = 20;

	var spacing:Float;
	var minIndex:Int = 0;
	var maxIndex:Int = -1;
	var numRows:Int = 3;
	var rowHeight:Int = 40;
	var seed:Int = 123456789;
	var lastBgCols:Int = -1;
	var lastBgRows:Int = -1;

	inline function rand():Float {
		seed ^= (seed << 13);
		seed ^= (seed >> 17);
		seed ^= (seed << 5);
		return (seed & 0x7FFFFFFF) / 2147483647.0;
	}

	public function new() {
		super();
		stage.align = StageAlign.TOP_LEFT;
		stage.scaleMode = StageScaleMode.NO_SCALE;

		// Background behind the world content
		background = new Sprite();
		addChild(background);

		world = new Sprite();
		addChild(world);

		spacing = (creatureSize * scaleFactor) + gap;

		// 1. Create a pool of reusable Bitmaps
		var viewW = Math.max(1, stage.stageWidth);
		var columnsVisible = Std.int(Math.ceil(viewW / spacing)) + 4;
		var neededBitmaps = Std.int(Math.max(columnsVisible, 12));
		for (i in 0...neededBitmaps) {
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
		stage.addEventListener(Event.RESIZE, onResize);
		stage.addEventListener(Event.REMOVED_FROM_STAGE, function(_) {
			stage.removeEventListener(Event.ENTER_FRAME, onEnterFrame);
			stage.removeEventListener(MouseEvent.MOUSE_WHEEL, onWheel);
			stage.removeEventListener(KeyboardEvent.KEY_DOWN, onKeyDown);
			stage.removeEventListener(Event.RESIZE, onResize);
		});

		// 2b. Initialize background after we know stage size
		initBackground();

		// 3. Initial population
		updateVisibleCreatures();

		// Initial layout
		onResize(null);
	}

    // --- Funky background -------------------------------------------------

    function initBackground():Void {
        // Choose a palette that complements creatures: prefer darker bases and one bright accent
        var palette = getRandomPalette();
        var filtered = filterBodyPalette(palette);
        if (filtered.length < 2) filtered = [0x2E1A47, 0x4B3F72, 0x6C5B7B];
        // pick two bases and an accent
        var i0 = Std.int(Math.random() * filtered.length);
        var i1 = Std.int(Math.random() * filtered.length);
        while (i1 == i0 && filtered.length > 1) i1 = Std.int(Math.random() * filtered.length);
        bgBaseColors = [darkenColor(filtered[i0], 0.55), darkenColor(filtered[i1], 0.75)];
        bgAccentColor = 0xE2E8F0; // soft bright for sparkles/stripes

        // Build a single tile bitmap data used by all tiles
        bgTileBD = generateBackgroundTile(bgTileSize, bgBaseColors, bgAccentColor);

        // Build grid of tiles to cover current stage
        rebuildBackgroundGrid();
    }

    function rebuildBackgroundGrid():Void {
        var viewW = Math.max(1, stage.stageWidth);
        var viewH = Math.max(1, stage.stageHeight);
        var cols = Std.int(Math.ceil(viewW / bgTileSize)) + 2;
        var rows = Std.int(Math.ceil(viewH / bgTileSize)) + 2;
        if (lastBgCols == cols && lastBgRows == rows) return; // already sized correctly
        lastBgCols = cols;
        lastBgRows = rows;

        // Clear existing tiles
        for (bmp in bgTiles) {
            if (bmp.parent != null) bmp.parent.removeChild(bmp);
        }
        bgTiles = [];

        for (r in 0...rows) {
            for (c in 0...cols) {
                var bmp = new Bitmap(bgTileBD);
                bmp.smoothing = false;
                bmp.pixelSnapping = PixelSnapping.ALWAYS;
                bmp.x = c * bgTileSize;
                bmp.y = r * bgTileSize;
                background.addChild(bmp);
                bgTiles.push(bmp);
            }
        }
        // Reset background position to align tiling
        background.x = 0;
        background.y = 0;
    }

    function generateBackgroundTile(size:Int, baseColors:Array<Int>, accent:Int):BitmapData {
        var bd = new BitmapData(size, size, false, 0x000000);

        // 4x4 Bayer matrix for ordered dithering
        var bayer:Array<Array<Int>> = [
            [0, 8, 2, 10],
            [12, 4, 14, 6],
            [3, 11, 1, 9],
            [15, 7, 13, 5]
        ];

        var c0 = baseColors[0];
        var c1 = baseColors[1 % baseColors.length];
        var stripePeriod = 16; // pixels between stripes
        var stripeWidth = 2;   // stripe thickness

        for (y in 0...size) {
            for (x in 0...size) {
                // Diagonal gradient coordinate (wrap for tiling)
                var t = (x + y) / (2 * size);
                var threshold = (bayer[y & 3][x & 3] + 0.5) / 16.0;
                var base = (t < threshold) ? c0 : c1;

                // Diagonal funky stripes (offset animates via bgDrift in rendering)
                var stripeCoord = (x + (y << 1)) % stripePeriod;
                if (stripeCoord < stripeWidth) {
                    base = darkenColor(base, 0.7);
                }

                // Sparse sparkles
                if (((x * 131 + y * 97) % 997) == 0 || ((x * 37 + y * 71) % 409) == 0) {
                    base = accent;
                }

                bd.setPixel(x, y, base);
            }
        }

        return bd;
    }

    function darkenColor(color:Int, factor:Float):Int {
        var r = Std.int(((color >> 16) & 0xFF) * factor);
        var g = Std.int(((color >> 8) & 0xFF) * factor);
        var b = Std.int((color & 0xFF) * factor);
        if (r < 0) r = 0; if (g < 0) g = 0; if (b < 0) b = 0;
        return (r << 16) | (g << 8) | b;
    }

	// Generate organic width profile for creature shape based on body type
	function generateWidthProfile(size:Int, minWidth:Int, maxWidth:Int, bodyType:BodyType):Array<Int> {
		var widths = new Array<Int>();
		var currentWidth = Std.int((minWidth + maxWidth) * 0.5);
		
		for (y in 0...size) {
			var t = y / (size - 1); // 0 to 1 from top to bottom
			var baseWidth = currentWidth;
			
			// Apply body type shaping
			switch (bodyType) {
				case Blob:
					// Circular profile
					var centerDist = Math.abs(t - 0.5) * 2; // 0 at center, 1 at edges
					baseWidth = Std.int(minWidth + (maxWidth - minWidth) * (1 - centerDist * centerDist));
				
				case Tall:
					// Narrow throughout, slight taper
					baseWidth = Std.int(minWidth + (maxWidth - minWidth) * (0.3 + 0.2 * Math.sin(t * Math.PI)));
				
				case Wide:
					// Broad, squat shape
					baseWidth = Std.int(minWidth + (maxWidth - minWidth) * (0.8 + 0.2 * Math.sin(t * Math.PI)));
				
				case Pear:
					// Narrow top, wide bottom
					baseWidth = Std.int(minWidth + (maxWidth - minWidth) * (0.3 + 0.7 * t * t));
				
				case Inverted:
					// Wide top, narrow bottom  
					var invT = 1 - t;
					baseWidth = Std.int(minWidth + (maxWidth - minWidth) * (0.3 + 0.7 * invT * invT));
				
				case Hourglass:
					// Wide-narrow-wide
					var hourFactor = Math.abs(Math.sin(t * Math.PI));
					baseWidth = Std.int(minWidth + (maxWidth - minWidth) * (0.4 + 0.6 * hourFactor));
			}
			
			// Add random walk for organic variation
			var step = Std.int((rand() - 0.5) * 2);
			currentWidth = baseWidth + step;
			
			// Clamp to reasonable bounds
			if (currentWidth < minWidth) currentWidth = minWidth;
			if (currentWidth > maxWidth) currentWidth = maxWidth;
			
			// Slight feathering at extremes
			var edgeFactor = 1.0;
			if (t < 0.1) edgeFactor = t * 10;
			if (t > 0.9) edgeFactor = (1 - t) * 10;
			
			var finalWidth = Std.int(currentWidth * edgeFactor);
			if (finalWidth < 1) finalWidth = 1;
			widths.push(finalWidth);
		}
		
		return widths;
	}

	// Add edge roughening to make creatures less geometric
	function roughenEdges(bmpData:BitmapData, size:Int, baseColor:Int):Void {
		for (y in 1...size-1) {
			// Find left and right edges
			var leftEdge = -1;
			var rightEdge = -1;
			
			for (x in 0...size) {
				var alpha = (bmpData.getPixel32(x, y) >>> 24) & 0xFF;
				if (alpha > 0 && leftEdge == -1) {
					leftEdge = x;
					break;
				}
			}
			
			for (x in 0...size) {
				var rx = size - 1 - x;
				var alpha = (bmpData.getPixel32(rx, y) >>> 24) & 0xFF;
				if (alpha > 0 && rightEdge == -1) {
					rightEdge = rx;
					break;
				}
			}
			
			if (leftEdge == -1 || rightEdge == -1) continue;
			
			// Random edge jittering
			if (rand() < 0.2 && leftEdge > 0) {
				// Sometimes remove edge pixel
				bmpData.setPixel32(leftEdge, y, 0x00000000);
			} else if (rand() < 0.15 && leftEdge > 0) {
				// Sometimes add pixel outside edge
				bmpData.setPixel32(leftEdge - 1, y, 0xFF000000 | baseColor);
			}
			
			if (rand() < 0.2 && rightEdge < size - 1) {
				// Sometimes remove edge pixel
				bmpData.setPixel32(rightEdge, y, 0x00000000);
			} else if (rand() < 0.15 && rightEdge < size - 1) {
				// Sometimes add pixel outside edge
				bmpData.setPixel32(rightEdge + 1, y, 0xFF000000 | baseColor);
			}
		}
	}

	// Add internal texture patterns to make creatures more interesting
	function addTexturePatterns(bmpData:BitmapData, size:Int, palette:Array<Int>):Void {
		var patternType = Std.int(rand() * 4); // 0-3
		if (patternType == 0) return; // No pattern
		
		var accentColor = palette[Std.int(rand() * palette.length)];
		
		switch (patternType) {
			case 1: // Spots
				var numSpots = 3 + Std.int(rand() * 5); // 3-7 spots
				for (i in 0...numSpots) {
					var sx = 2 + Std.int(rand() * (size - 4));
					var sy = 2 + Std.int(rand() * (size - 4));
					var spotSize = 1 + Std.int(rand() * 2); // 1-2 pixel radius
					
					for (dx in -spotSize...spotSize+1) {
						for (dy in -spotSize...spotSize+1) {
							var px = sx + dx;
							var py = sy + dy;
							if (px >= 0 && px < size && py >= 0 && py < size) {
								// Only add spot if there's already a pixel there
								var existing = (bmpData.getPixel32(px, py) >>> 24) & 0xFF;
								if (existing > 0 && rand() < 0.6) {
									bmpData.setPixel32(px, py, 0xFF000000 | accentColor);
									// Mirror to other side
									var mirrorX = size - 1 - px;
									bmpData.setPixel32(mirrorX, py, 0xFF000000 | accentColor);
								}
							}
						}
					}
				}
				
			case 2: // Horizontal stripes
				var stripeSpacing = 3 + Std.int(rand() * 3); // 3-5
				for (y in 0...size) {
					if (y % stripeSpacing == 0) {
						for (x in 0...size) {
							var existing = (bmpData.getPixel32(x, y) >>> 24) & 0xFF;
							if (existing > 0 && rand() < 0.4) {
								bmpData.setPixel32(x, y, 0xFF000000 | accentColor);
							}
						}
					}
				}
				
			case 3: // Vertical gradient effect
				var gradientColor = palette[Std.int(rand() * palette.length)];
				for (y in 0...size) {
					var gradientStrength = y / (size - 1); // 0 to 1
					if (rand() < gradientStrength * 0.3) { // Stronger at bottom
						for (x in 0...size) {
							var existing = (bmpData.getPixel32(x, y) >>> 24) & 0xFF;
							if (existing > 0 && rand() < 0.3) {
								bmpData.setPixel32(x, y, 0xFF000000 | gradientColor);
							}
						}
					}
				}
		}
	}

	// Add subtle asymmetric details while keeping overall bilateral symmetry
	function addAsymmetricDetails(bmpData:BitmapData, size:Int, palette:Array<Int>):Void {
		if (rand() < 0.7) return; // Only 30% chance of asymmetric details
		
		var detailColor = palette[Std.int(rand() * palette.length)];
		var detailType = Std.int(rand() * 3);
		
		switch (detailType) {
			case 0: // Single side marking/scar
				var side = rand() < 0.5 ? -1 : 1; // Left or right
				var markX = (size >> 1) + side * (2 + Std.int(rand() * 3));
				var markY = 4 + Std.int(rand() * (size - 8));
				
				if (markX >= 0 && markX < size) {
					// Vertical scar/marking
					for (dy in 0...3) {
						var py = markY + dy;
						if (py >= 0 && py < size) {
							var existing = (bmpData.getPixel32(markX, py) >>> 24) & 0xFF;
							if (existing > 0) {
								bmpData.setPixel32(markX, py, 0xFF000000 | detailColor);
							}
						}
					}
				}
				
			case 1: // Single eye wink (only if creature has 2 eyes)
				// Find existing eyes and randomly "close" one
				var cx = size >> 1;
				var eyeY = 3 + Std.int(rand() * 4);
				var side = rand() < 0.5 ? -1 : 1;
				var winkX = cx + side * 3;
				
				if (winkX >= 0 && winkX < size) {
					var existing = (bmpData.getPixel32(winkX, eyeY) >>> 24) & 0xFF;
					if (existing > 0) {
						// Replace eye with a horizontal line
						bmpData.setPixel32(winkX, eyeY, 0xFF000000 | 0xFFFFFF);
						bmpData.setPixel32(winkX, eyeY + 1, 0x00000000); // Remove pupil
					}
				}
				
			case 2: // Small asymmetric spot
				var side = rand() < 0.5 ? -1 : 1;
				var spotX = (size >> 1) + side * (1 + Std.int(rand() * 4));
				var spotY = 6 + Std.int(rand() * (size - 10));
				
				if (spotX >= 0 && spotX < size) {
					var existing = (bmpData.getPixel32(spotX, spotY) >>> 24) & 0xFF;
					if (existing > 0) {
						bmpData.setPixel32(spotX, spotY, 0xFF000000 | detailColor);
						// Maybe add a second pixel
						if (rand() < 0.5 && spotY + 1 < size) {
							var existing2 = (bmpData.getPixel32(spotX, spotY + 1) >>> 24) & 0xFF;
							if (existing2 > 0) {
								bmpData.setPixel32(spotX, spotY + 1, 0xFF000000 | detailColor);
							}
						}
					}
				}
		}
	}

	function makeCreatureData(size:Int, density:Float, palette:Array<Int>):BitmapData {
		var bmpData = new BitmapData(size, size, true, 0x00000000);
		bmpData.lock();

		var bodyPalette = filterBodyPalette(palette);
		var baseColor = bodyPalette[Std.int(rand() * bodyPalette.length)];
		var accentColor = bodyPalette[Std.int(rand() * bodyPalette.length)];
		var eyeY = 3 + Std.int(rand() * 4); // randomize eye position
		
		// Select random body type
		var bodyTypes = [BodyType.Blob, BodyType.Tall, BodyType.Wide, BodyType.Pear, BodyType.Inverted, BodyType.Hourglass];
		var bodyType = bodyTypes[Std.int(rand() * bodyTypes.length)];
		
		// Generate organic width profile based on body type
		var minWidth = 2 + Std.int(rand() * 2); // 2-3
		var maxWidth = 5 + Std.int(rand() * 3); // 5-7
		var widthProfile = generateWidthProfile(size, minWidth, maxWidth, bodyType);
		
		// Body: fill using width profile with density variation
		for (y in 0...size) {
			var maxHalfWidth = widthProfile[y];
			var localDensity = density;
			
			// Reduce density near face area
			if (y >= eyeY - 2 && y <= eyeY + 2)
				localDensity *= 0.6;
			
			for (x in 0...maxHalfWidth) {
				if (rand() < localDensity) {
					var useAccent = rand() < 0.2;
					var color = useAccent ? accentColor : baseColor;
					bmpData.setPixel32(x, y, 0xFF000000 | color);
					bmpData.setPixel32(size - 1 - x, y, 0xFF000000 | color);
				}
			}
		}

		// Apply edge roughening for organic look
		roughenEdges(bmpData, size, baseColor);

		// Add internal texture patterns
		addTexturePatterns(bmpData, size, bodyPalette);

		// Clear a small face area so eyes/mouth are visible
		carveFaceArea(bmpData, size, eyeY);

		addEyes(bmpData, size, eyeY);
		addMouth(bmpData, size);
		addHorns(bmpData, size, palette);

		// Add subtle asymmetric details last
		addAsymmetricDetails(bmpData, size, bodyPalette);

		bmpData.unlock();
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
		var bg = 0x00000000;
		var cx = size >> 1;
		var mouthY = size - 4; // match where mouth will be placed

		// Larger face window: from eyes to mouth
		for (y in (eyeY - 1)...(mouthY + 2)) {
			for (x in (cx - 4)...(cx + 5)) {
				if (x >= 0 && x < size && y >= 0 && y < size) {
					bmpData.setPixel32(x, y, bg);
				}
			}
		}
	}

	function addEyes(bmpData:BitmapData, size:Int, eyeY:Int):Void {
		var numEyes = 1 + Std.int(rand() * 3); // 1-3 eyes
		var eyeColor = 0xFFFFFF;
		var pupilColor = 0x000000;
		var cx = size >> 1;
		var spacing = 2 + Std.int(rand() * 3); // 2-4 spacing
		
		// Randomize eye Y position slightly
		var actualEyeY = eyeY + Std.int((rand() - 0.5) * 2);
		if (actualEyeY < 1) actualEyeY = 1;
		if (actualEyeY >= size - 2) actualEyeY = size - 3;

		switch (numEyes) {
			case 1:
				// Single centered eye
				bmpData.setPixel32(cx, actualEyeY, 0xFF000000 | eyeColor);
				bmpData.setPixel32(cx, actualEyeY + 1, 0xFF000000 | pupilColor);
			case 2:
				// Two eyes with random spacing
				var l = cx - spacing;
				var r = cx + spacing;
				if (l >= 0) {
					bmpData.setPixel32(l, actualEyeY, 0xFF000000 | eyeColor);
					bmpData.setPixel32(l, actualEyeY + 1, 0xFF000000 | pupilColor);
				}
				if (r < size) {
					bmpData.setPixel32(r, actualEyeY, 0xFF000000 | eyeColor);
					bmpData.setPixel32(r, actualEyeY + 1, 0xFF000000 | pupilColor);
				}
			case 3:
				// Three eyes
				var l3 = cx - spacing;
				var r3 = cx + spacing;
				if (l3 >= 0) {
					bmpData.setPixel32(l3, actualEyeY, 0xFF000000 | eyeColor);
					bmpData.setPixel32(l3, actualEyeY + 1, 0xFF000000 | pupilColor);
				}
				bmpData.setPixel32(cx, actualEyeY, 0xFF000000 | eyeColor);
				bmpData.setPixel32(cx, actualEyeY + 1, 0xFF000000 | pupilColor);
				if (r3 < size) {
					bmpData.setPixel32(r3, actualEyeY, 0xFF000000 | eyeColor);
					bmpData.setPixel32(r3, actualEyeY + 1, 0xFF000000 | pupilColor);
				}
		}
		
		// Occasional special eye effects
		if (rand() < 0.1) {
			// Glowing eyes - add extra white pixels around
			for (dx in -1...2) {
				for (dy in -1...2) {
					if (dx == 0 && dy == 0) continue;
					var ex = cx + dx;
					var ey = actualEyeY + dy;
					if (ex >= 0 && ex < size && ey >= 0 && ey < size && rand() < 0.3) {
						bmpData.setPixel32(ex, ey, 0xFF000000 | 0xCCCCCC);
					}
				}
			}
		}
	}

	function addMouth(bmpData:BitmapData, size:Int):Void {
		var mouthType = Std.int(rand() * 5); // 0-4, with 4 being no mouth
		if (mouthType == 4) return; // No mouth

		// Randomize mouth position slightly
		var mouthY = size - 4 + Std.int((rand() - 0.5) * 2);
		if (mouthY < size - 6) mouthY = size - 6;
		if (mouthY >= size - 1) mouthY = size - 2;
		
		var centerX = size >> 1;
		var mouthColor = 0xFFFFFF;

		switch (mouthType) {
			case 0: // happy

				for (dx in -3...4) {
					bmpData.setPixel32(centerX + dx, mouthY, 0xFF000000 | mouthColor);
				}
				// curve up at edges
				bmpData.setPixel32(centerX - 4, mouthY - 1, 0xFF000000 | mouthColor);
				bmpData.setPixel32(centerX + 4, mouthY - 1, 0xFF000000 | mouthColor);

			case 1: // big frown
				// mouth row
				for (dx in -3...4) {
					bmpData.setPixel32(centerX + dx, mouthY + 1, 0xFF000000 | mouthColor);
				}
				// curve down at edges
				bmpData.setPixel32(centerX - 4, mouthY + 2, 0xFF000000 | mouthColor);
				bmpData.setPixel32(centerX + 4, mouthY + 2, 0xFF000000 | mouthColor);
				// thicker top lip
				for (dx in -2...3) {
					bmpData.setPixel32(centerX + dx, mouthY, 0xFF000000 | mouthColor);
				}

			case 2: // open mouth
				// outer shape
				for (dx in -2...3) {
					bmpData.setPixel32(centerX + dx, mouthY, 0xFF000000 | mouthColor);
					bmpData.setPixel32(centerX + dx, mouthY + 2, 0xFF000000 | mouthColor);
				}
				bmpData.setPixel32(centerX - 3, mouthY + 1, 0xFF000000 | mouthColor);
				bmpData.setPixel32(centerX + 3, mouthY + 1, 0xFF000000 | mouthColor);
				// fill inside with a different color (tongue)
				var tongueColor = 0xFF4B4B; // bright red
				for (dx in -1...2) {
					bmpData.setPixel32(centerX + dx, mouthY + 1, 0xFF000000 | tongueColor);
				}
		}
	}

	function addHorns(bmpData:BitmapData, size:Int, palette:Array<Int>):Void {
		var hornType = Std.int(rand() * 6); // 0-5, with 0 being no horns
		if (hornType == 0) return; // No horns

		// Randomize horn color - sometimes use palette, sometimes bright colors
		var hornColor:Int;
		if (rand() < 0.7) {
			hornColor = 0xFFFF00; // bright yellow
		} else {
			var hornColors = [0xFF4444, 0x44FF44, 0x4444FF, 0xFF44FF, 0xFFFFFF];
			hornColor = hornColors[Std.int(rand() * hornColors.length)];
		}
		
		var centerX = size >> 1;
		
		// Randomize horn positioning slightly
		var hornOffset = Std.int((rand() - 0.5) * 2); // -1, 0, or 1

		switch (hornType) {
			case 1: // Simple spikes
				var lx = centerX - 3 + hornOffset;
				var rx = centerX + 3 + hornOffset;
				if (lx >= 0) bmpData.setPixel32(lx, 0, 0xFF000000 | hornColor);
				if (rx < size) bmpData.setPixel32(rx, 0, 0xFF000000 | hornColor);
				
			case 2: // Thick spikes
				var lx = centerX - 2 + hornOffset;
				var rx = centerX + 2 + hornOffset;
				if (lx >= 0) {
					bmpData.setPixel32(lx, 0, 0xFF000000 | hornColor);
					bmpData.setPixel32(lx, 1, 0xFF000000 | hornColor);
				}
				if (rx < size) {
					bmpData.setPixel32(rx, 0, 0xFF000000 | hornColor);
					bmpData.setPixel32(rx, 1, 0xFF000000 | hornColor);
				}

			case 3: // Curved horns
				var lx = centerX - 2 + hornOffset;
				var rx = centerX + 2 + hornOffset;
				// Left horn
				if (lx >= 0 && lx - 2 >= 0) {
					bmpData.setPixel32(lx, 0, 0xFF000000 | hornColor);
					bmpData.setPixel32(lx, 1, 0xFF000000 | hornColor);
					bmpData.setPixel32(lx - 1, 1, 0xFF000000 | hornColor);
					bmpData.setPixel32(lx - 1, 2, 0xFF000000 | hornColor);
					bmpData.setPixel32(lx - 2, 3, 0xFF000000 | hornColor);
				}
				// Right horn
				if (rx < size && rx + 2 < size) {
					bmpData.setPixel32(rx, 0, 0xFF000000 | hornColor);
					bmpData.setPixel32(rx, 1, 0xFF000000 | hornColor);
					bmpData.setPixel32(rx + 1, 1, 0xFF000000 | hornColor);
					bmpData.setPixel32(rx + 1, 2, 0xFF000000 | hornColor);
					bmpData.setPixel32(rx + 2, 3, 0xFF000000 | hornColor);
				}
				
			case 4: // Single center horn
				var cx = centerX + hornOffset;
				if (cx >= 0 && cx < size) {
					bmpData.setPixel32(cx, 0, 0xFF000000 | hornColor);
					bmpData.setPixel32(cx, 1, 0xFF000000 | hornColor);
					if (rand() < 0.5) bmpData.setPixel32(cx, 2, 0xFF000000 | hornColor);
				}
				
			case 5: // Asymmetric horns
				var lx = centerX - 2 + hornOffset;
				var rx = centerX + 3 + hornOffset;
				if (lx >= 0) bmpData.setPixel32(lx, 0, 0xFF000000 | hornColor);
				if (rx < size) {
					bmpData.setPixel32(rx, 0, 0xFF000000 | hornColor);
					bmpData.setPixel32(rx, 1, 0xFF000000 | hornColor);
				}
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
		return palettes[Std.int(rand() * palettes.length)];
	}

	function onWheel(e:MouseEvent):Void {
		world.x -= e.delta * 40;
		clampScroll();
	}

	function onKeyDown(e:KeyboardEvent):Void {
		var step = 40;
		if (e.keyCode == Keyboard.RIGHT)
			world.x -= step;
		if (e.keyCode == Keyboard.LEFT)
			world.x += step;
		#if sys
		if (e.keyCode == Keyboard.S) {
			var i = 0;
			for (index in activeCreatures.keys()) {
				var bmp = activeCreatures.get(index);
				if (bmp != null && bmp.bitmapData != null) {
					saveCreaturePNG(bmp.bitmapData, "Export/neko/bin/exports/creature_" + i + ".png");
					i++;
				}
			}
		}
		#end
		clampScroll();
	}

	function onResize(_:Event):Void {
		this.scrollRect = new Rectangle(0, 0, stage.stageWidth, stage.stageHeight);
		// Resize background coverage
		rebuildBackgroundGrid();
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
		// Parallax background drift
		bgDrift += 0.25; // slow autonomous drift
		var ox = ((world.x * bgParallax + bgDrift) % bgTileSize + bgTileSize) % bgTileSize;
		var oy = ((Math.sin(bgDrift * 0.01) * 20) % bgTileSize + bgTileSize) % bgTileSize;
		background.x = -ox;
		background.y = -oy;

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
					var density = 0.2 + rand() * 0.6;
					var palette = getRandomPalette();
					if (bmp.bitmapData != null) bmp.bitmapData.dispose();
					bmp.bitmapData = makeCreatureData(creatureSize, density, palette);
					bmp.x = margin + i * spacing;
					var row = ((i % numRows) + numRows) % numRows;
					bmp.y = 100 + row * rowHeight;
					bmp.visible = true;
					activeCreatures.set(i, bmp);
					if (maxIndex < minIndex) { minIndex = i; maxIndex = i; }
					if (i < minIndex) minIndex = i;
					if (i > maxIndex) maxIndex = i;
				}
			}
		}
		contentWidth = margin * 2 + (maxIndex - minIndex + 1) * spacing;
	}

	function findAvailableBitmap():Bitmap {
		for (bmp in creaturePool) {
			if (!bmp.visible)
				return bmp;
		}
		// Steal the farthest visible one if pool exhausted
		var farBmp:Bitmap = null;
		var farDist:Float = -1e9;
		var farIndex:Int = 0;
		for (pair in activeCreatures.keyValueIterator()) {
			var idx = pair.key;
			var b = pair.value;
			var dist = Math.abs((margin + idx * spacing) + world.x - stage.stageWidth * 0.5);
			if (dist > farDist) { farDist = dist; farBmp = b; farIndex = idx; }
		}
		if (farBmp != null) {
			activeCreatures.remove(farIndex);
		}
		return farBmp;
	}

	#if sys
	function saveCreaturePNG(bmpData:BitmapData, filePath:String):Void {
		var bytes = bmpData.encode(bmpData.rect, new PNGEncoderOptions());
		sys.io.File.saveBytes(filePath, bytes);
	}
	#end
}
