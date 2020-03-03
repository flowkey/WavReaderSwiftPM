//
//  wavHeader.h
//  WavReader
//
//  Created by Geordie Jay on 03.03.20.
//  Copyright © 2020 flowkey. All rights reserved.
//

#ifndef wavHeader_h
#define wavHeader_h

struct FmtChunk {
    unsigned char fmtChunkString[4];
    unsigned int lengthOfFmtSection;
    unsigned short formatType; // 1 == PCM is the only supported format
    unsigned short channelCount;
    unsigned int sampleRate;
    unsigned int byteRate;
    unsigned short blockAlignment;
    unsigned short bitsPerSample;
};

struct DataChunk {
    unsigned char dataChunkString[4];
    unsigned int dataSize;
};

#endif /* wavHeader_h */
