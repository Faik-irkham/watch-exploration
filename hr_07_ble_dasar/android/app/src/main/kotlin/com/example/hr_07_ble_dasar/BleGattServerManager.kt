package com.example.hr_07_ble_dasar

import android.annotation.SuppressLint
import android.bluetooth.*
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.content.Context
import android.os.ParcelUuid
import android.util.Log
import java.util.UUID
import java.util.concurrent.CopyOnWriteArraySet

/**
 * Logika GATT Server + Advertising BLE
 *
 * Kontrak dengan app phone (hr_08): SATU notify per interval, dikirim
 * tepat saat bacaan valid didapat. Tidak ada pengiriman ulang dan tidak
 * ada antrean — kalau saat itu tidak ada phone yang subscribe, bacaan
 * tersebut hanya tersimpan di SQLite watch.
 */

@SuppressLint("MissingPermission")
class BleGattServerManager(private val context: Context) {

  companion object {
    private const val TAG = "BLE_SERVER"
    val SERVICE_UUID: UUID = UUID.fromString("12345678-1234-5678-1234-56789abcdef0")
    val CHAR_UUID: UUID = UUID.fromString("abcdef01-1234-5678-1234-56789abcdef0")
    val CCCD_UUID: UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")
  }

  private val bluetoothManager =
        context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
  private val bluetoothAdapter = bluetoothManager.adapter

  private var advertiser = bluetoothAdapter?.bluetoothLeAdvertiser
  private var gattServer: BluetoothGattServer? = null
  private var hrCharacteristic: BluetoothGattCharacteristic? = null

  // Diakses dari Binder thread (callback GATT) DAN main thread (updateBpm),
  // jadi wajib koleksi yang aman-thread. Set biasa bisa melempar
  // ConcurrentModificationException tepat saat notify sedang berjalan.
  private val subscribedDevices = CopyOnWriteArraySet<BluetoothDevice>()

  /** Bacaan terakhir, hanya untuk melayani request READ / debugging (nRF Connect). */
  @Volatile private var lastBpm: Int = 0

  private val advertiseCallback = object : AdvertiseCallback() {
    override fun onStartSuccess(settingsInEffect: AdvertiseSettings?) {
      Log.d(TAG, "Berhasil memancarkan sinyal BLE (Advertising)!")
      LiveUpdateBridge.emitBleStatus("broadcasting")
    }
    override fun onStartFailure(errorCode: Int) {
      Log.e(TAG, "Gagal memancarkan sinyal: $errorCode")
      LiveUpdateBridge.emitBleStatus("error", "Gagal memancarkan sinyal BLE (kode $errorCode)")
    }
  }

  private val gattServerCallback = object : BluetoothGattServerCallback() {
    /**
     * addService() itu asinkron. Advertising baru boleh mulai di sini,
     * setelah service benar-benar terdaftar — kalau tidak, phone bisa
     * connect lalu discoverServices() duluan dan tidak menemukan
     * characteristic apa pun.
     */
    override fun onServiceAdded(status: Int, service: BluetoothGattService?) {
      if (status != BluetoothGatt.GATT_SUCCESS) {
        Log.e(TAG, "Gagal menambah GATT service: $status")
        LiveUpdateBridge.emitBleStatus("error", "Gagal mendaftarkan GATT service (kode $status)")
        return
      }
      startAdvertising()
    }

    override fun onConnectionStateChange(device: BluetoothDevice, status: Int, newState: Int) {
      if (newState == BluetoothProfile.STATE_DISCONNECTED) {
          // Subscribe dilepas saat putus; phone harus tulis CCCD lagi
          // setelah reconnect supaya terdaftar kembali.
          subscribedDevices.remove(device)
          Log.d(TAG, "Device terputus: ${device.address}")
      }
    }

    override fun onCharacteristicReadRequest(
      device: BluetoothDevice, requestId: Int, offset: Int,
      characteristic: BluetoothGattCharacteristic
    ) {
      // Characteristic dideklarasikan PROPERTY_READ, jadi request READ
      // wajib dijawab. Tanpa handler ini request-nya menggantung sampai timeout.
      if (characteristic.uuid != CHAR_UUID) {
        gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_FAILURE, 0, null)
        return
      }
      val payload = byteArrayOf(lastBpm.coerceIn(0, 255).toByte())
      gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, 0, payload)
    }

    override fun onDescriptorReadRequest(
      device: BluetoothDevice, requestId: Int, offset: Int,
      descriptor: BluetoothGattDescriptor
    ) {
      if (descriptor.uuid == CCCD_UUID) {
        val value = if (subscribedDevices.contains(device)) {
          BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
        } else {
          BluetoothGattDescriptor.DISABLE_NOTIFICATION_VALUE
        }
        gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, 0, value)
      } else {
        gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_FAILURE, 0, null)
      }
    }

    override fun onDescriptorWriteRequest(
      device: BluetoothDevice, requestId: Int, descriptor: BluetoothGattDescriptor,
      preparedWrite: Boolean, responseNeeded: Boolean, offset: Int, value: ByteArray?
    ) {
      if (descriptor.uuid == CCCD_UUID) {
        // Catat siapa yang benar-benar subscribe, jangan asal broadcast ke
        // semua yang terhubung.
        val enabled = value != null &&
            value.contentEquals(BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE)
        if (enabled) {
          subscribedDevices.add(device)
          Log.d(TAG, "Device subscribe notify: ${device.address}")
        } else {
          subscribedDevices.remove(device)
        }
        if (responseNeeded) {
          gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, 0, null)
        }
      } else if (responseNeeded) {
        gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_FAILURE, 0, null)
      }
    }
  }

  fun start(): Boolean {
    if (bluetoothAdapter == null || !bluetoothAdapter.isEnabled) {
        LiveUpdateBridge.emitBleStatus("error", "Bluetooth mati atau tidak didukung perangkat.")
        return false
    }

    stop()

    return try {
        val server = bluetoothManager.openGattServer(context, gattServerCallback)
        if (server == null) {
            LiveUpdateBridge.emitBleStatus("error", "Gagal membuka GATT Server")
            return false
        }
        gattServer = server

        val service = BluetoothGattService(SERVICE_UUID, BluetoothGattService.SERVICE_TYPE_PRIMARY)
        val characteristic = BluetoothGattCharacteristic(
            CHAR_UUID,
            BluetoothGattCharacteristic.PROPERTY_READ or BluetoothGattCharacteristic.PROPERTY_NOTIFY,
            BluetoothGattCharacteristic.PERMISSION_READ
        )
        characteristic.addDescriptor(
            BluetoothGattDescriptor(
                CCCD_UUID,
                BluetoothGattDescriptor.PERMISSION_WRITE or BluetoothGattDescriptor.PERMISSION_READ
            )
        )
        service.addCharacteristic(characteristic)
        hrCharacteristic = characteristic

        // Advertising menyusul di onServiceAdded(), bukan di sini.
        server.addService(service)
        true
    } catch (e: SecurityException) {
        LiveUpdateBridge.emitBleStatus("error", "Izin Bluetooth ditolak: ${e.message}")
        false
    } catch (e: Exception) {
        LiveUpdateBridge.emitBleStatus("error", "Error BLE: ${e.message}")
        false
    }
  }

  private fun startAdvertising() {
    val settings = AdvertiseSettings.Builder()
        .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
        .setConnectable(true)
        .setTimeout(0)
        .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
        .build()

    val data = AdvertiseData.Builder()
        .addServiceUuid(ParcelUuid(SERVICE_UUID))
        .build()

    val currentAdvertiser = bluetoothAdapter?.bluetoothLeAdvertiser
    advertiser = currentAdvertiser
    if (currentAdvertiser == null) {
        LiveUpdateBridge.emitBleStatus("error", "Perangkat tidak mendukung BLE Advertiser")
        return
    }

    try {
        currentAdvertiser.startAdvertising(settings, data, advertiseCallback)
    } catch (e: Exception) {
        LiveUpdateBridge.emitBleStatus("error", "Gagal memulai advertising: ${e.message}")
    }
  }

  fun stop() {
    try {
        advertiser?.stopAdvertising(advertiseCallback)
        gattServer?.clearServices()
        gattServer?.close()
    } catch (e: Exception) {
        Log.e(TAG, "Error saat stop(): ${e.message}")
    } finally {
        subscribedDevices.clear()
        gattServer = null
        hrCharacteristic = null
        LiveUpdateBridge.emitBleStatus("stopped")
    }
  }

  /**
   * Kirim 1 nilai bpm ke semua perangkat yang sedang subscribe.
   * Dipanggil tepat sekali per interval dari HeartRateBleService.
   *
   * @return true kalau notify terkirim ke minimal satu perangkat.
   */
  fun updateBpm(bpm: Int): Boolean {
    val clamped = bpm.coerceIn(0, 255)
    lastBpm = clamped

    val char = hrCharacteristic ?: return false
    val server = gattServer ?: return false

    if (subscribedDevices.isEmpty()) {
        Log.d(TAG, "Tidak ada phone yang subscribe, bpm $clamped hanya disimpan lokal.")
        return false
    }

    // Payload custom ini 1 byte unsigned (0..255) — cukup untuk bpm
    // wajar. Sisi penerima WAJIB baca sebagai unsigned:
    // value[0].toInt() and 0xFF
    char.value = byteArrayOf(clamped.toByte())

    var delivered = false
    for (device in subscribedDevices) {
        try {
            if (server.notifyCharacteristicChanged(device, char, false)) {
                delivered = true
            }
        } catch (e: Exception) {
            Log.e(TAG, "Gagal notify ke ${device.address}: ${e.message}")
            subscribedDevices.remove(device)
        }
    }
    Log.d(TAG, "Kirim bpm $clamped ke ${subscribedDevices.size} device, sukses=$delivered")
    return delivered
  }
}
