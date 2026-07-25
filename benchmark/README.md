# Benchmarks

Store versioned benchmark inputs, raw CSV or JSON results, and a concise written
interpretation here. Each run must identify the host/runtime, model file and
quantization, inference settings, client location, concurrency, prompt set, and
measurement method.

For a controlled performance benchmark, record at minimum TTFT, prompt
processing throughput, generation throughput, P95 latency, model load time, CPU
use, and memory use where they can be measured. A deployment smoke observation
may record a smaller set when it is explicitly classified as non-comparative.
Never compare runs with materially different settings without stating the
difference.
