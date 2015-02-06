package webm;

import cpp.Lib;
import flash.display.Bitmap;
import flash.display.BitmapData;
import flash.display.PixelSnapping;
import flash.events.Event;
import flash.events.SampleDataEvent;
import flash.media.Sound;
import flash.utils.ByteArray;
import flash.utils.Endian;
import haxe.io.Bytes;
import haxe.io.BytesData;

using Std;

class WebmPlayer extends Bitmap
{
	static inline var BYTES_PER_SAMPLE = 4 * 8192;
	static var BLANK_BYTES:ByteArray;

	public var frameRate(default, null):Float;
	public var duration(default, null):Float;

	var vpxDecoder:VpxDecoder;
	var webmDecoder:Dynamic;
	var outputSound:ByteArray;
	var sound:Sound;
	
	var startTime = 0.0;
	var lastDecodedVideoFrame = 0.0;
	var playing = false;
	var renderedCount = 0;

	public function new(resource:String)
	{
		super(null);

		if (BLANK_BYTES == null)
		{
			BLANK_BYTES = new ByteArray();
			for (i in 0...BYTES_PER_SAMPLE)
				BLANK_BYTES.writeByte(0);
		}

		pixelSnapping = PixelSnapping.AUTO;
		smoothing = true;

		vpxDecoder = new VpxDecoder();

		var io = new WebmIoFile(resource);
		webmDecoder = hx_webm_decoder_create(io.io);
		
		var info = hx_webm_decoder_get_info(webmDecoder);
		bitmapData = new BitmapData(info[0].int(), info[1].int());
		frameRate = info[2];
		duration = info[3];

		outputSound = new ByteArray();
		outputSound.endian = Endian.LITTLE_ENDIAN;
		
		sound = new Sound();
		sound.addEventListener(SampleDataEvent.SAMPLE_DATA, generateSound);
		sound.play();
	}

	public function generateSound(e:SampleDataEvent)
	{
		if (e.data == null)
			e.data = new ByteArray();

		var totalOutputLength = outputSound.length;
		var outputBytesToWrite = Math.min(totalOutputLength, BYTES_PER_SAMPLE).int();
		var blankBytesToWrite = BYTES_PER_SAMPLE - outputBytesToWrite;

		if (blankBytesToWrite > 0)
			e.data.writeBytes(BLANK_BYTES, 0, blankBytesToWrite);

		if (outputBytesToWrite > 0)
		{
			e.data.writeBytes(outputSound, 0, outputBytesToWrite);

			if (outputBytesToWrite < totalOutputLength)
			{
				var remainingBytes = new ByteArray();
				remainingBytes.writeBytes(outputSound, outputBytesToWrite);
				outputSound = remainingBytes;
			}
			else
			{
				outputSound.clear();
			}
		}
	}
	
	public function getElapsedTime():Float
	{
		return haxe.Timer.stamp() - startTime;
	}
	
	public function play()
	{
		if (!playing)
		{
			startTime = haxe.Timer.stamp();

			addEventListener(Event.ENTER_FRAME, onSpriteEnterFrame);
			playing = true;
			dispatchEvent(new Event('play'));
		}
	}

	public function stop()
	{
		if (playing)
		{
			removeEventListener(Event.ENTER_FRAME, onSpriteEnterFrame);
			playing = false;
			dispatchEvent(new Event('stop'));
		}
	}
	
	function onSpriteEnterFrame(e:Event)
	{
		var startRenderedCount = renderedCount;

		while (hx_webm_decoder_has_more(webmDecoder) && lastDecodedVideoFrame < getElapsedTime())
		{
			hx_webm_decoder_step(webmDecoder, decodeVideoFrame, outputAudioFrame);
			if (renderedCount > startRenderedCount) break;
		}
		
		if (!hx_webm_decoder_has_more(webmDecoder))
		{
			dispatchEvent(new Event('end'));
			stop();
		}
	}

	function decodeVideoFrame(time:Float, data:BytesData)
	{
		lastDecodedVideoFrame = time;
		++renderedCount;
		
		vpxDecoder.decode(ByteArray.fromBytes(Bytes.ofData(data)));
		vpxDecoder.getAndRenderFrame(bitmapData);
	}
	
	function outputAudioFrame(time:Float, data:BytesData)
	{
		outputSound.position = outputSound.length;
		outputSound.writeBytes(ByteArray.fromBytes(Bytes.ofData(data)));
		outputSound.position = 0;
	}
	
	static var hx_webm_decoder_create:Dynamic -> Dynamic = Lib.load("openfl-webm", "hx_webm_decoder_create", 1);
	static var hx_webm_decoder_get_info:Dynamic -> Array<Float> = Lib.load("openfl-webm", "hx_webm_decoder_get_info", 1);
	static var hx_webm_decoder_has_more:Dynamic -> Bool = Lib.load("openfl-webm", "hx_webm_decoder_has_more", 1);
	static var hx_webm_decoder_step = Lib.load("openfl-webm", "hx_webm_decoder_step", 3);
}