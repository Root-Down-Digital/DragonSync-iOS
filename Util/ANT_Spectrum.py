#!/usr/bin/env python3

import sys
import time
import zmq
import argparse
import numpy as np
from threading import Thread, Event
import iio
from scipy import signal

class ANTSDRSpectrumAnalyzer:
    def __init__(self, uri="ip:192.168.1.10", buffer_size=1024, sample_rate=30.72e6, averaging=8):
        self.ctx = iio.Context(uri)
        self.phy = self.ctx.find_device("ad9361-phy")
        self.rx = self.ctx.find_device("cf-ad9361-lpc")
        self.buffer_size = buffer_size
        self.sample_rate = sample_rate
        self.center_freq = 915e6
        self.bandwidth = 20e6
        self.rx_gain = 50.0
        self.stop_signal = Event()
        self.window = signal.windows.hann(buffer_size)
        self.spectrum_buffer = []
        self.averaging = averaging

    def configure_device(self):
        self.phy.channels[0].attrs["frequency"].value = str(int(self.center_freq))
        self.phy.channels[0].attrs["sampling_frequency"].value = str(int(self.sample_rate))
        self.phy.channels[0].attrs["rf_bandwidth"].value = str(int(self.bandwidth))
        self.phy.channels[0].attrs["hardwaregain"].value = str(int(self.rx_gain))
        self.rx_channel = self.rx.channels[0]
        self.rx_buffer = iio.Buffer(self.rx, self.buffer_size, False)

    def get_spectrum_data(self):
        self.rx_buffer.refill()
        data = self.rx_buffer.read()
        samples = np.frombuffer(data, dtype=np.int16)
        iq = samples[::2] + 1j * samples[1::2]
        
        segments = signal.windows.get_window('hann', self.buffer_size)
        freqs, times, Sxx = signal.spectrogram(iq, window=segments, 
                                             noverlap=int(self.buffer_size * 0.75))
        
        if len(self.spectrum_buffer) >= self.averaging:
            self.spectrum_buffer.pop(0)
        self.spectrum_buffer.append(10 * np.log10(np.abs(Sxx)))
        
        return np.mean(self.spectrum_buffer, axis=0)

    def start_streaming(self, zmq_socket):
        self.configure_device()
        while not self.stop_signal.is_set():
            try:
                spectrum_data = self.get_spectrum_data()
                freq_points = np.linspace(
                    self.center_freq - self.bandwidth/2,
                    self.center_freq + self.bandwidth/2,
                    len(spectrum_data)
                )
                
                data_dict = {
                    "timestamp": time.time(),
                    "center_freq": self.center_freq,
                    "bandwidth": self.bandwidth,
                    "sample_rate": self.sample_rate,
                    "gain": self.rx_gain,
                    "spectrum": spectrum_data.tolist(),
                    "frequency_points": freq_points.tolist()
                }
                zmq_socket.send_json(data_dict)
                time.sleep(0.1)
            except Exception as e:
                print(f"Streaming error: {e}")
                break

    def stop_streaming(self):
        self.stop_signal.set()

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--uri", default="ip:192.168.1.10", help="ANTSDR URI")
    parser.add_argument("--zmq-host", default="0.0.0.0", help="ZMQ host")
    parser.add_argument("--zmq-port", type=int, default=4226, help="ZMQ port")
    parser.add_argument("--buffer-size", type=int, default=1024, help="Buffer size")
    parser.add_argument("--sample-rate", type=float, default=30.72e6, help="Sample rate")
    parser.add_argument("--averaging", type=int, default=8, help="Number of averages")
    args = parser.parse_args()

    context = zmq.Context()
    socket = context.socket(zmq.PUB)
    socket.bind(f"tcp://{args.zmq_host}:{args.zmq_port}")

    analyzer = ANTSDRSpectrumAnalyzer(
        args.uri, 
        args.buffer_size, 
        args.sample_rate, 
        args.averaging
    )
    stream_thread = Thread(target=analyzer.start_streaming, args=(socket,))
    stream_thread.start()

    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        analyzer.stop_streaming()
        stream_thread.join()
        socket.close()
        context.term()

if __name__ == "__main__":
    main()