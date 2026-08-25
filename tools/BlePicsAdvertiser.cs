using System;
using System.Threading;
using Windows.Devices.Bluetooth.Advertisement;
using Windows.Storage.Streams;

internal static class BlePicsAdvertiser
{
    private static int Main()
    {
        var publisher = new BluetoothLEAdvertisementPublisher();
        var manufacturer = new BluetoothLEManufacturerData { CompanyId = 0x01CE };
        var writer = new DataWriter();
        var payload = new byte[] {
            0x58, 0x01, 0x02, 0x01, 0x00, 0x00,
            0xDE, 0xAD, 0xBE, 0xEF,
            0xFF, 0x73, 0xFF, 0xFF, 0xFF, 0xFF,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
        };

        writer.WriteBytes(payload);
        manufacturer.Data = writer.DetachBuffer();
        publisher.Advertisement.ManufacturerData.Add(manufacturer);

        try
        {
            publisher.Start();
            Thread.Sleep(1500);
            Console.WriteLine("Publisher status: " + publisher.Status);
            if (publisher.Status != BluetoothLEAdvertisementPublisherStatus.Started)
            {
                return 2;
            }

            Console.WriteLine("Broadcasting CompanyId=0x01CE ID=DEADBEEF Type=2 for 15 seconds");
            Thread.Sleep(15000);
            return 0;
        }
        finally
        {
            publisher.Stop();
            Thread.Sleep(500);
            Console.WriteLine("Final status: " + publisher.Status);
            writer.Dispose();
        }
    }
}

