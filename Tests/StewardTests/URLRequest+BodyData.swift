import Foundation

extension URLRequest {
    func bodyData() -> Data? {
        if let httpBody {
            return httpBody
        }

        guard let httpBodyStream else {
            return nil
        }

        httpBodyStream.open()
        defer { httpBodyStream.close() }

        var data = Data()
        let bufferSize = 1024
        var buffer = [UInt8](repeating: 0, count: bufferSize)

        while httpBodyStream.hasBytesAvailable {
            let bytesRead = httpBodyStream.read(&buffer, maxLength: bufferSize)

            if bytesRead < 0 {
                return nil
            }

            if bytesRead == 0 {
                break
            }

            data.append(buffer, count: bytesRead)
        }

        return data
    }
}
