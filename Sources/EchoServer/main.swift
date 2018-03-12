import NIO

private final class EchoHandler: ChannelInboundHandler {
    public typealias InboundIn = ByteBuffer
    public typealias OutboundOut = ByteBuffer

    // Keep tracks of the number of message received in a single session
    // (an EchoHandler is created per client connection).
    private var count: Int = 0

    // Invoked on client connection
    public func channelRegistered(ctx: ChannelHandlerContext) {
        print("channel registered:", ctx.remoteAddress ?? "unknown")
    }

    // Invoked on client disconnect
    public func channelUnregistered(ctx: ChannelHandlerContext) {
        print("we have processed \(count) messages")
    }

    // Invoked when data are received from the client
    public func channelRead(ctx: ChannelHandlerContext, data: NIOAny) {
        ctx.write(data, promise: nil)
        count = count + 1
    }

    // Invoked when channelRead as processed all the read event in the current read operation
    public func channelReadComplete(ctx: ChannelHandlerContext) {
        ctx.flush()
    }

    // Invoked when an error occurs
    public func errorCaught(ctx: ChannelHandlerContext, error: Error) {
        print("error: ", error)
        ctx.close(promise: nil)
    }
}

// Create a multi thread even loop to use all the system core for the processing
let group = MultiThreadedEventLoopGroup(numThreads: System.coreCount)

// Set up the server using a Bootstrap
let bootstrap = ServerBootstrap(group: group)
        // Define backlog and enable SO_REUSEADDR options atethe server level
        .serverChannelOption(ChannelOptions.backlog, value: 256)
        .serverChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)

        // Handler Pipeline: handlers that are processing events from accepted Channels
        // To demonstrate that we can have several reusable handlers we start with a Swift-NIO default
        // handler that limits the speed at which we read from the client if we cannot keep up with the
        // processing through EchoHandler.
        // This is to protect the server from overload.
        .childChannelInitializer { channel in
            channel.pipeline.add(handler: BackPressureHandler()).then { v in
                channel.pipeline.add(handler: EchoHandler())
            }
        }

        // Enable common socket options at the channel level (TCP_NODELAY and SO_REUSEADDR).
        // These options are applied to accepted Channels
        .childChannelOption(ChannelOptions.socket(IPPROTO_TCP, TCP_NODELAY), value: 1)
        .childChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
        // Message grouping
        .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 16)
        // Let Swift-NIO adjust the buffer size, based on actual trafic.
        .childChannelOption(ChannelOptions.recvAllocator, value: AdaptiveRecvByteBufferAllocator())
defer {
    try! group.syncShutdownGracefully()
}

// Bind the port and run the server
let channel = try bootstrap.bind(host: "::1", port: 9999).wait()

print("Server started and listening on \(channel.localAddress!)")

// Clean-up (never called, as we do not have a code to decide when to stop
// the server). We assume we will be killing it with Ctrl-C.
try channel.closeFuture.wait()

print("Server terminated")

