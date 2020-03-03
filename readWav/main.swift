//
//  main.swift
//  readWav
//
//  Created by Geordie Jay on 03.03.20.
//  Copyright © 2020 flowkey. All rights reserved.
//

let wavFile = try WavFile(filename: "example.wav", blockSize: 1024)

for block in wavFile {
    print(block)
}
