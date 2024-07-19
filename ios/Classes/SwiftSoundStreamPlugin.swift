import Flutter
import UIKit
import AVFoundation

public enum SoundStreamErrors: String {
    case FailedToRecord
    case FailedToPlay
    case FailedToStop
    case FailedToWriteBuffer
    case FailedToSetStereoVolume
    case Unknown
}

public enum SoundStreamStatus: String {
    case Unset
    case Initialized
    case Playing
    case Stopped
}

@available(iOS 9.0, *)
public class SwiftSoundStreamPlugin: NSObject, FlutterPlugin {
    private var channel: FlutterMethodChannel
    private var registrar: FlutterPluginRegistrar
    private var debugLogging: Bool = false

    //========= Recorder's vars
    private let mAudioEngine = AVAudioEngine()

    //========= Player's vars
    private let PLAYER_OUTPUT_SAMPLE_RATE: Double = 32000   // 32Khz
    private let mPlayerBus = 0
    private var isUsingSpeaker: Bool = false
    private let mPlayerNode = AVAudioPlayerNode()
    private var mPlayerSampleRate: Double = 16000 // 16Khz
    private var mPlayerBufferSize: AVAudioFrameCount = 8192
    private var mPlayerOutputFormat: AVAudioFormat!
    private var mPlayerInputFormat: AVAudioFormat!
    private var mPlayerLeftGain: Float = 1.000
    private var mPlayerRightGain: Float = 1.000

    /** ======== Basic Plugin initialization ======== **/

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "vn.casperpas.sound_stream:methods", binaryMessenger: registrar.messenger())
        let instance = SwiftSoundStreamPlugin( channel, registrar: registrar)
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    init( _ channel: FlutterMethodChannel, registrar: FlutterPluginRegistrar ) {
        self.channel = channel
        self.registrar = registrar

        super.init()
        self.attachPlayer()
        mAudioEngine.prepare()
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "initializePlayer":
            initializePlayer(call, result)
        case "startPlayer":
            startPlayer(result)
        case "stopPlayer":
            stopPlayer(result)
        case "writeChunk":
            writeChunk(call, result)
        case "setStereoVolume":
            setStereoVolume(call, result)
        default:
            print("Unrecognized method: \(call.method)")
            sendResult(result, FlutterMethodNotImplemented)
        }
    }

    private func sendResult(_ result: @escaping FlutterResult, _ arguments: Any?) {
        DispatchQueue.main.async {
            result( arguments )
        }
    }

    private func invokeFlutter( _ method: String, _ arguments: Any? ) {
        DispatchQueue.main.async {
            self.channel.invokeMethod( method, arguments: arguments )
        }
    }

    /** ======== Plugin methods ======== **/

    private func startEngine() {
        guard !mAudioEngine.isRunning else {
            return
        }

        try? mAudioEngine.start()
    }

    private func sendEventMethod(_ name: String, _ data: Any) {
        var eventData: [String: Any] = [:]
        eventData["name"] = name
        eventData["data"] = data
        invokeFlutter("platformEvent", eventData)
    }

    private func initializePlayer(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        guard let argsArr = call.arguments as? Dictionary<String,AnyObject>
        else {
            sendResult(result, FlutterError( code: SoundStreamErrors.Unknown.rawValue,
                                             message:"Incorrect parameters",
                                             details: nil ))
            return
        }
        mPlayerSampleRate = argsArr["sampleRate"] as? Double ?? mPlayerSampleRate
        debugLogging = argsArr["showLogs"] as? Bool ?? debugLogging
        mPlayerInputFormat = AVAudioFormat(commonFormat: AVAudioCommonFormat.pcmFormatInt16, sampleRate: mPlayerSampleRate, channels: 1, interleaved: true)
        sendPlayerStatus(SoundStreamStatus.Initialized)
    }

    private func attachPlayer() {
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false)
        try! session.setCategory(
            .playAndRecord,
            options: [
                .defaultToSpeaker,
                .allowBluetooth,
                .allowBluetoothA2DP,
                .allowAirPlay
            ])
        try! session.setActive(true)
        mPlayerOutputFormat = AVAudioFormat(commonFormat: AVAudioCommonFormat.pcmFormatFloat32, sampleRate: PLAYER_OUTPUT_SAMPLE_RATE, channels: 1, interleaved: true)

        mAudioEngine.attach(mPlayerNode)
        mAudioEngine.connect(mPlayerNode, to: mAudioEngine.mainMixerNode, format: mPlayerOutputFormat)
        setUsePhoneSpeaker(false)
    }

    private func startPlayer(_ result: @escaping FlutterResult) {
        startEngine()
        if !mPlayerNode.isPlaying {
            mPlayerNode.play()
        }
        sendPlayerStatus(SoundStreamStatus.Playing)
        result(true)
    }

    private func stopPlayer(_ result: @escaping FlutterResult) {
        if mPlayerNode.isPlaying {
            mPlayerNode.stop()
        }
        sendPlayerStatus(SoundStreamStatus.Stopped)
        result(true)
    }

    private func sendPlayerStatus(_ status: SoundStreamStatus) {
        sendEventMethod("playerStatus", status.rawValue)
    }

    private func writeChunk(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        guard let argsArr = call.arguments as? Dictionary<String,AnyObject>,
              let data = argsArr["data"] as? FlutterStandardTypedData
        else {
            sendResult(result, FlutterError( code: SoundStreamErrors.FailedToWriteBuffer.rawValue,
                                             message:"Failed to write Player buffer",
                                             details: nil ))
            return
        }
        let byteData = [UInt8](data.data)
        pushPlayerChunk(byteData, result)
    }

    private func setUsePhoneSpeaker(_ enabled: Bool) {
        if mPlayerNode.isPlaying {
            mPlayerNode.stop()
            sendPlayerStatus(SoundStreamStatus.Stopped)
        }

        let avAudioSession = AVAudioSession.sharedInstance()

        if enabled {
            try? avAudioSession.overrideOutputAudioPort(AVAudioSession.PortOverride.speaker)
        } else {
            try? avAudioSession.overrideOutputAudioPort(AVAudioSession.PortOverride.none)
        }

        if debugLogging {
            print("OUTPUTS")
            for output in avAudioSession.currentRoute.outputs{
                print(output.portName)
            }
        }

        try? avAudioSession.setActive(true)

        isUsingSpeaker = enabled
        startEngine()
    }

    private func pushPlayerChunk(_ chunk: [UInt8], _ result: @escaping FlutterResult) {
        let buffer = bytesToAudioBuffer(chunk)
        mPlayerNode.scheduleBuffer(convertBufferFormat(
            buffer,
            from: mPlayerInputFormat,
            to: mPlayerOutputFormat
        ));
        result(true)
    }

    private func convertBufferFormat(_ buffer: AVAudioPCMBuffer, from: AVAudioFormat, to: AVAudioFormat) -> AVAudioPCMBuffer {

        let formatConverter =  AVAudioConverter(from: from, to: to)
        let ratio: Float = Float(from.sampleRate)/Float(to.sampleRate)
        let pcmBuffer = AVAudioPCMBuffer(pcmFormat: to, frameCapacity: UInt32(Float(buffer.frameCapacity) / ratio))!

        var error: NSError? = nil
        let inputBlock: AVAudioConverterInputBlock = {inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }
        formatConverter?.convert(to: pcmBuffer, error: &error, withInputFrom: inputBlock)

        return pcmBuffer
    }

    private func audioBufferToBytes(_ audioBuffer: AVAudioPCMBuffer) -> [UInt8] {
        let srcLeft = audioBuffer.int16ChannelData![0]
        let bytesPerFrame = audioBuffer.format.streamDescription.pointee.mBytesPerFrame
        let numBytes = Int(bytesPerFrame * audioBuffer.frameLength)

        // initialize bytes by 0
        var audioByteArray = [UInt8](repeating: 0, count: numBytes)

        srcLeft.withMemoryRebound(to: UInt8.self, capacity: numBytes) { srcByteData in
            audioByteArray.withUnsafeMutableBufferPointer {
                $0.baseAddress!.initialize(from: srcByteData, count: numBytes)
            }
        }

        return audioByteArray
    }

    private func bytesToAudioBuffer(_ buf: [UInt8]) -> AVAudioPCMBuffer {
        let frameLength = UInt32(buf.count) / mPlayerInputFormat.streamDescription.pointee.mBytesPerFrame

        let audioBuffer = AVAudioPCMBuffer(pcmFormat: mPlayerInputFormat, frameCapacity: frameLength)!
        audioBuffer.frameLength = frameLength

        let dstLeft = audioBuffer.int16ChannelData![0]

        buf.withUnsafeBufferPointer {
            let src = UnsafeRawPointer($0.baseAddress!).bindMemory(to: Int16.self, capacity: Int(frameLength))
            dstLeft.initialize(from: src, count: Int(frameLength))
        }

        return audioBuffer
    }

    private func setStereoVolume(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        guard let argsArr = call.arguments as? Dictionary<String,NSNumber>
        else {
            sendResult(result, FlutterError( code: SoundStreamErrors.Unknown.rawValue,
                                             message:"Incorrect parameters",
                                             details: nil ))
            return
        }

        mPlayerLeftGain = argsArr["leftGain"]?.floatValue ?? mPlayerLeftGain
        mPlayerRightGain = argsArr["rightGain"]?.floatValue ?? mPlayerRightGain
        var newPan: Float = mPlayerRightGain < 1 ? mPlayerRightGain - 1.000 : 1.000 - mPlayerLeftGain
        if debugLogging {
            print("starting setStereoVolume, leftGain: \(mPlayerLeftGain), rightGain: \(mPlayerRightGain), newPan: \(newPan)")
        }

        do {
            mPlayerNode.pan = newPan
            result(true)
        } catch {
            result(FlutterError(code: SoundStreamErrors.FailedToSetStereoVolume.rawValue, 
                                message: "Failed to set stereo volume", 
                                details: nil))
        }
    }
}
