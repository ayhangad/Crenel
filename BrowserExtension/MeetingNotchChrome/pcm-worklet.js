class MeetingNotchPCMChunker extends AudioWorkletProcessor {
  constructor() {
    super();
    this.channels = [];
    this.frameCount = 0;
    this.targetFrameCount = 960;
  }

  process(inputs) {
    const input = inputs[0];
    if (!input || input.length === 0 || input[0].length === 0) return true;

    if (this.channels.length === 0) {
      this.channels = Array.from({ length: Math.min(input.length, 2) }, () => []);
    }
    const frames = input[0].length;
    for (let channel = 0; channel < this.channels.length; channel += 1) {
      const source = input[channel] ?? input[0];
      for (let frame = 0; frame < frames; frame += 1) {
        this.channels[channel].push(source[frame]);
      }
    }
    this.frameCount += frames;

    if (this.frameCount >= this.targetFrameCount) {
      const interleaved = new Float32Array(this.frameCount * this.channels.length);
      for (let frame = 0; frame < this.frameCount; frame += 1) {
        for (let channel = 0; channel < this.channels.length; channel += 1) {
          interleaved[(frame * this.channels.length) + channel] = this.channels[channel][frame];
        }
      }
      this.port.postMessage({
        samples: interleaved,
        sampleRate,
        channels: this.channels.length,
      }, [interleaved.buffer]);
      this.channels.forEach((channel) => { channel.length = 0; });
      this.frameCount = 0;
    }
    return true;
  }
}

registerProcessor("meetingnotch-pcm-chunker", MeetingNotchPCMChunker);
