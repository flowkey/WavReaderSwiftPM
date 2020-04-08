import Foundation

var wavReaderIterator: WavReader.Iterator? = nil

@_cdecl("initialize")
public func initialize(filePath: UnsafePointer<CChar>, blockSize: CInt) {
    let filename = try! String(cString: filePath)
    print("initialize with file: ", filename)
    wavReaderIterator = try! WavReader(
        filename: filename,
        blockSize: Int(blockSize)
    ).makeIterator()
}

@_cdecl("get_next_block")
public func getNextBlock(ptr: UnsafeMutablePointer<CFloat>) -> CInt {
    guard let wavReaderIterator = wavReaderIterator else {
        return 1
    }

    guard var block = wavReaderIterator.next() else {
        return 2
    }

    ptr.assign(from: &block, count: block.count)

    return 0
}