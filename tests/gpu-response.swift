// Measure the production GPU reader before/during/after a bounded Metal workload.
// Run: bash scripts/verify-gpu-response.sh; prints only synthetic timing and usage.
// Requires Apple Silicon macOS, Metal and the built telemetry object.
import Foundation
import Metal
@main struct GPUResponse {
    static func main() throws {
        guard let device=MTLCreateSystemDefaultDevice(),let queue=device.makeCommandQueue() else{fatalError("Metal unavailable")}
        let source="""
        #include <metal_stdlib>
        using namespace metal;
        kernel void work(device float *out [[buffer(0)]], uint id [[thread_position_in_grid]]) {
            float x=float(id)*0.00001f+0.5f;
            for(uint i=0;i<32768;i++)x=sin(x)*0.999f+0.51f;
            out[id]=x;
        }
        """
        let library=try device.makeLibrary(source:source,options:nil)
        let pipeline=try device.makeComputePipelineState(function:library.makeFunction(name:"work")!)
        let count=262144
        guard let buffer=device.makeBuffer(length:count*4,options:.storageModeShared) else{fatalError("Allocation failed")}
        final class Timeline:@unchecked Sendable {
            let lock=NSLock();var spans:[[Double]]=[]
            func add(_ start:Double,_ end:Double){lock.lock();spans.append([start,end]);lock.unlock()}
        }
        let timeline=Timeline()
        let origin=ProcessInfo.processInfo.systemUptime
        var samples:[[String:Any]]=[]
        func sample(_ phase:String){let value=ts_gpu();samples.append(["phase":phase,"seconds":ProcessInfo.processInfo.systemUptime-origin,"valid":value.valid,"percent":value.valid ? value.percent as Any:NSNull()])}
        func observe(_ phase:String,_ duration:Double){let end=ProcessInfo.processInfo.systemUptime+duration;while ProcessInfo.processInfo.systemUptime<end{sample(phase);Thread.sleep(forTimeInterval:0.2)}}
        observe("before",3)
        let group=DispatchGroup();group.enter()
        DispatchQueue.global(qos:.utility).async {
            defer{group.leave()};let end=ProcessInfo.processInfo.systemUptime+4
            while ProcessInfo.processInfo.systemUptime<end {
                autoreleasepool {
                    let command=queue.makeCommandBuffer()!,encoder=command.makeComputeCommandEncoder()!
                    encoder.setComputePipelineState(pipeline);encoder.setBuffer(buffer,offset:0,index:0)
                    encoder.dispatchThreads(MTLSize(width:count,height:1,depth:1),threadsPerThreadgroup:MTLSize(width:128,height:1,depth:1))
                    encoder.endEncoding();command.commit();command.waitUntilCompleted()
                    precondition(command.status == .completed,"Metal workload failed")
                    timeline.add(command.gpuStartTime-origin,command.gpuEndTime-origin)
                }
            }
        }
        observe("load",4);group.wait();observe("after",3);ts_close()
        let data=try JSONSerialization.data(withJSONObject:["sample_interval_seconds":0.2,"workload":"4-second bounded Metal compute","samples":samples,"gpu_command_intervals":timeline.spans],options:[.prettyPrinted,.sortedKeys])
        FileHandle.standardOutput.write(data)
    }
}
