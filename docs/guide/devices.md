# Devices

Once one device is connected to your server (see [Sync](sync.md)), you can add your other devices. Each device you add can read and sync all your journals.

## Add a device

Each way below gives the new device your journals without your server ever seeing the key that protects them.

### iPhone or iPad: scan a code

1. On a device that already syncs, choose Settings > Devices > **Add Device…**. It shows a code.
2. On the new iPhone or iPad, open My Journal, choose **Connect to a Server…**, then **Scan Code**, and point the camera at the code.
3. On the device that shows the code, check the name of the new device and add it. With Touch ID or a passcode, confirming is the only step; with Face ID, choose **Add Device** first.

The new device then downloads your journals. There’s no address to type and no code to compare: the scanned code tells the new device where your server is and proves both devices are yours. The code changes every two minutes and disappears when you leave the app. Scan Code appears only on a device that doesn’t have journals yet.

### Any device: sign in with your master password

1. On the new device, choose **Connect to a Server…**. Your server appears under **Servers on This Network** when you’re on the same network as it (see [self-hosting](../self-hosting/README.md)); otherwise enter its address and choose **Continue**.
2. Check that the server named under **Sign In to** is yours, enter your master password, and choose **Connect**.

If this device already has journals, choose Settings > Sync > **Connect to a Server…** instead. Its journals are added to the server next to the others; with a code from a connected device, you confirm this with **Connect and Upload**.

### Any device: use a code from a connected device

If you’d rather not type your master password, for example on a Mac:

1. On the new device, choose the server as above, then **Use a Connected Device Instead…**. A pairing code appears.
2. On a device that already syncs, choose Settings > Devices > **Add Device…** > **Enter Code Instead…**, enter the pairing code and choose **Continue**.
3. Both devices show a six-digit check code. If it’s the same on both, choose **Approve** on the device you already use and **Connect** on the new device, in either order. On the Mac, the shortcut for both is ⌘Return.

If the codes don’t match, choose **Cancel** on both devices; nothing is shared. If the pairing code expires before you enter it, choose **Get New Code**.

For journals without encryption, whoever runs the server creates a one-time recovery code (see [self-hosting](../self-hosting/README.md#recovering-an-unencrypted-library)). Choose **Use a Recovery Code** and enter it.

## See your devices

Settings > Devices lists every device that can sync, with how and when it was added, for example “Added by MacBook Pro on 28 Sep 2026”. The one you’re using is marked This Device. iPhones and iPads usually appear by their model name, such as iPhone.

## Remove a device

Remove a device you no longer use, or one that was lost or given away:

1. On another device, choose Settings > Devices.
2. Under the device, choose **Revoke Access…**, then **Revoke Access**.

This stops future sync for that device. Journals already on it stay there and can’t be erased remotely. A device can’t revoke itself; to remove your journals from a device you still have, see [Delete your data](troubleshooting.md#delete-your-data).
