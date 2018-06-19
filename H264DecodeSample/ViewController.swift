//
//  ViewController.swift
//  H264DecodeSample
//
//  Created by Tomoya Hirano on 2018/06/20.
//  Copyright © 2018年 Tomoya Hirano. All rights reserved.
//

import UIKit
import VideoToolbox

final class ViewController: UIViewController {
  
  override func viewDidLoad() {
    super.viewDidLoad()
    decode()
  }
  
  func decode() {
    // h264ファイルのオープン
    let url = Bundle.main.url(forResource: "sample2", withExtension: "h264")!
    let stream = InputStream(url: url)!
    stream.open()
    
    // 0x05のnalTypeを持つデータを探す
    var isFind0x05 = false
    //
    var continueData = [UInt8]()
    var sps: Array<UInt8>?
    var pps: Array<UInt8>?
    
    var data: [UInt8] = []
    while !isFind0x05 {
      if continueData.count > 0 { //前回の残りがある場合
        data = continueData
      } else {
        // バイナリデータの取得
        let capacity: Int = 512 * 1024
        var temp = Array<UInt8>(repeating: 0, count: capacity)
        let length = stream.read(&temp, maxLength: capacity)
        data = Array(temp[0..<length])
      }
      // スタートコードの確認
      let startCode: [UInt8] = [0,0,0,1]
      if Array(data[0...3]) != startCode {
        preconditionFailure()
      }
      // 次のスタートコードまでを取得
      var offset = 0
      var isFindNextStartCode = false
      offset += 4 // 最初のスタートコードは除外
      while !isFindNextStartCode {
        if Array(data[offset...offset+3]) == startCode {
          continueData = Array(data[offset..<data.count])
          data.removeSubrange(offset..<data.count)
          isFindNextStartCode = true
        }
        offset += 1
      }
      
      //スタートコードを除去（ちょっとよくわかってない）
      var biglen = CFSwapInt32HostToBig(UInt32(data.count - 4))
      memcpy(&data, &biglen, 4)
      //nal typeが画像フレームの0x06かチェック（ちょっとよくわかってない）
      let nalType = String(format: "0x%02x", data[4] & 0x1F)
      if nalType == "0x05" {
        isFind0x05 = true
      } else if nalType == "0x07" {
        sps = Array(data[4..<data.count])
      } else if nalType == "0x08" {
        pps = Array(data[4..<data.count])
      }
    }
    
    //完了するとこのコールバックが呼ばれる
    var callback = VTDecompressionOutputCallbackRecord()
    callback.decompressionOutputCallback = { (_, _, _, _, imageBuffer, _, _) in
      print("done")
      let imageBuffer = imageBuffer!
      let ciImage = CIImage(cvImageBuffer: imageBuffer)
      let image = UIImage(ciImage: ciImage)
      print(image)
    }
    
    //フレームの情報を生成
    var formatDesc: CMVideoFormatDescription?
    let spsPtr = UnsafePointer<UInt8>(sps!)
    let ppsPtr = UnsafePointer<UInt8>(pps!)
    let dataParams = [spsPtr, ppsPtr]
    let dataParamsPtr = UnsafePointer<UnsafePointer<UInt8>>(dataParams)
    let sizeParams = [sps!.count, pps!.count]
    let sizeParamsPtr = UnsafePointer<Int>(sizeParams)
    CMVideoFormatDescriptionCreateFromH264ParameterSets(kCFAllocatorDefault, 2, dataParamsPtr, sizeParamsPtr, 4, &formatDesc)
    
    //セッションの生成
    var session : VTDecompressionSession?
    let attributes = [kCVPixelBufferPixelFormatTypeKey : kCVPixelFormatType_420YpCbCr8BiPlanarFullRange] as CFDictionary
    VTDecompressionSessionCreate(kCFAllocatorDefault, formatDesc!, nil, attributes, &callback, &session)
    
    //ブロックバッファの生成
    let bufferPointer = UnsafeMutablePointer<UInt8>(mutating: data)
    var blockBuffer: CMBlockBuffer?
    CMBlockBufferCreateWithMemoryBlock(kCFAllocatorDefault, bufferPointer, data.count, kCFAllocatorNull, nil, 0, data.count, 0, &blockBuffer)
    
    //サンプルバッファの生成
    var sampleBuffer: CMSampleBuffer?
    let sampleSizeArray = [data.count]
    CMSampleBufferCreateReady(kCFAllocatorDefault, blockBuffer, formatDesc, 1, 0, nil, 1, sampleSizeArray, &sampleBuffer)
    
    //デコード実行
    VTDecompressionSessionDecodeFrame(session!, sampleBuffer!, [._EnableAsynchronousDecompression], nil, nil)
  }
  
}

