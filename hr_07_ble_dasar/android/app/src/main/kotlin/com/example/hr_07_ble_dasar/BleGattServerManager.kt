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

/**
 * Logika GATT Server + Advertising BLE
 * 
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
  private val connectedDevices = mutableSetOf<BluetoothDevice>()

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
    override fun onConnectionStateChange(device: BluetoothDevice, status: Int, newState: Int) {
      if (newState == BluetoothProfile.STATE_CONNECTED) {
          connectedDevices.add(device)
      } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
          connectedDevices.remove(device)
      }
    }

    override fun onDescriptorWriteRequest(
      device: BluetoothDevice, requestId: Int, descriptor: BluetoothGattDescriptor,
      preparedWrite: Boolean, responseNeeded: Boolean, offset: Int, value: ByteArray?
    ) {
      if (descriptor.uuid == CCCD_UUID && responseNeeded) {
          gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, 0, null)
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
        server.addService(service)
        hrCharacteristic = characteristic

        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
            .setConnectable(true)
            .setTimeout(0)
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
            .build()

        val data = AdvertiseData.Builder()
            .setIncludeDeviceName(true)
            .addServiceUuid(ParcelUuid(SERVICE_UUID))
            .build()

        val currentAdvertiser = bluetoothAdapter.bluetoothLeAdvertiser
        advertiser = currentAdvertiser
        if (currentAdvertiser == null) {
            LiveUpdateBridge.emitBleStatus("error", "Perangkat tidak mendukung BLE Advertiser")
            return false
        }

        currentAdvertiser.startAdvertising(settings, data, advertiseCallback)
        true
    } catch (e: SecurityException) {
        LiveUpdateBridge.emitBleStatus("error", "Izin Bluetooth ditolak: ${e.message}")
        false
    } catch (e: Exception) {
        LiveUpdateBridge.emitBleStatus("error", "Error BLE: ${e.message}")
        false
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
        connectedDevices.clear()
        gattServer = null
        hrCharacteristic = null
        LiveUpdateBridge.emitBleStatus("stopped")
    }
  }

  /** Kirim 1 nilai bpm baru ke semua perangkat yang sedang subscribe. */
  fun updateBpm(bpm: Int) {
    val char = hrCharacteristic ?: return
    // Payload custom ini 1 byte unsigned (0..255) — cukup untuk bpm
    // wajar. Sisi penerima WAJIB baca sebagai unsigned:
    // value[0].toInt() and 0xFF
    val clamped = bpm.coerceIn(0, 255)
    char.value = byteArrayOf(clamped.toByte())
    for (device in connectedDevices) {
        gattServer?.notifyCharacteristicChanged(device, char, false)
    }
  }
}