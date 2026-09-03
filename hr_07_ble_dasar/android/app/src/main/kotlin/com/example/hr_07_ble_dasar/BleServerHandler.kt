package com.example.hr_07_ble_dasar

import android.annotation.SuppressLint
import android.bluetooth.*
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.content.Context
import android.os.ParcelUuid
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.UUID

@SuppressLint("MissingPermission")
class BleServerHandler(private val context: Context) : MethodChannel.MethodCallHandler {

  private val bluetoothManager = context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
  private val bluetoothAdapter = bluetoothManager.adapter
  private var advertiser = bluetoothAdapter?.bluetoothLeAdvertiser
  private var gattServer: BluetoothGattServer? = null
  
  // Menyimpan daftar perangkat (HP/Treadmill) yang sedang terhubung ke jam
  private val connectedDevices = mutableSetOf<BluetoothDevice>()
  private var hrCharacteristic: BluetoothGattCharacteristic? = null

  // ==========================================
  // TENTUKAN CUSTOM UUID ANDA DI SINI
  // ==========================================
  private val SERVICE_UUID = UUID.fromString("12345678-1234-5678-1234-56789abcdef0")
  private val CHAR_UUID = UUID.fromString("abcdef01-1234-5678-1234-56789abcdef0")
  
  // CCCD (Client Characteristic Configuration Descriptor)
  // Ini UUID standar wajib dari Bluetooth SIG agar perangkat lain bisa "Subscribe/Notify" data kita
  private val CCCD_UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")

  // CALLBACK UNTUK PENYIARAN (ADVERTISING)
  private val advertiseCallback = object : AdvertiseCallback() {
      override fun onStartSuccess(settingsInEffect: AdvertiseSettings?) {
          Log.d("BLE_SERVER", "Berhasil memancarkan sinyal BLE (Advertising)!")
      }
      override fun onStartFailure(errorCode: Int) {
          Log.e("BLE_SERVER", "Gagal memancarkan sinyal: $errorCode")
      }
  }

  // CALLBACK UNTUK GATT SERVER (Menangani koneksi & permintaan data dari perangkat lain)
  private val gattServerCallback = object : BluetoothGattServerCallback() {
      override fun onConnectionStateChange(device: BluetoothDevice, status: Int, newState: Int) {
          if (newState == BluetoothProfile.STATE_CONNECTED) {
              Log.d("BLE_SERVER", "Perangkat terhubung: ${device.address}")
              connectedDevices.add(device)
          } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
              Log.d("BLE_SERVER", "Perangkat terputus: ${device.address}")
              connectedDevices.remove(device)
          }
      }

      // Ketika HP meminta izin untuk "Subscribe" (mendapatkan notifikasi saat detak jantung berubah)
      override fun onDescriptorWriteRequest(
          device: BluetoothDevice, requestId: Int, descriptor: BluetoothGattDescriptor,
          preparedWrite: Boolean, responseNeeded: Boolean, offset: Int, value: ByteArray?
      ) {
          if (descriptor.uuid == CCCD_UUID) {
              if (responseNeeded) {
                  gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, 0, null)
              }
          }
      }
  }

  // FUNGSI UNTUK MEMULAI SERVER & PEMANCAR
  private fun startBroadcasting() {
      if (bluetoothAdapter == null || !bluetoothAdapter.isEnabled) return

      // 1. Bangun GATT Server
      gattServer = bluetoothManager.openGattServer(context, gattServerCallback)

      // 2. Siapkan Service & Characteristic (Ruang & Laci)
      val service = BluetoothGattService(SERVICE_UUID, BluetoothGattService.SERVICE_TYPE_PRIMARY)
      hrCharacteristic = BluetoothGattCharacteristic(
          CHAR_UUID,
          BluetoothGattCharacteristic.PROPERTY_READ or BluetoothGattCharacteristic.PROPERTY_NOTIFY,
          BluetoothGattCharacteristic.PERMISSION_READ
      )

      // Tambahkan Descriptor CCCD agar fitur Notify bekerja
      val cccdDescriptor = BluetoothGattDescriptor(CCCD_UUID, BluetoothGattDescriptor.PERMISSION_WRITE or BluetoothGattDescriptor.PERMISSION_READ)
      hrCharacteristic?.addDescriptor(cccdDescriptor)

      service.addCharacteristic(hrCharacteristic)
      gattServer?.addService(service)

      // 3. Mulai Memancarkan Sinyal (Advertising)
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

      advertiser = bluetoothAdapter.bluetoothLeAdvertiser
      advertiser?.startAdvertising(settings, data, advertiseCallback)
  }

  // FUNGSI MENGHENTIKAN SERVER
  private fun stopBroadcasting() {
      advertiser?.stopAdvertising(advertiseCallback)
      gattServer?.clearServices()
      gattServer?.close()
      connectedDevices.clear()
  }

  // FUNGSI UNTUK MENGIRIM ANGKA DETAK JANTUNG BARU KE HP YANG TERHUBUNG
  private fun updateBpm(bpm: Int) {
      hrCharacteristic?.let { char ->
          // Mengubah angka Integer menjadi ByteArray (format standar pengiriman data BLE)
          char.value = byteArrayOf(bpm.toByte()) 
          
          // Beritahu (Notify) semua perangkat yang terhubung bahwa ada data baru
          for (device in connectedDevices) {
              gattServer?.notifyCharacteristicChanged(device, char, false)
          }
      }
  }

  // ==========================================
  // ENTRY POINT PERINTAH DARI FLUTTER (DART)
  // ==========================================
  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
      when (call.method) {
          "startBroadcasting" -> {
              startBroadcasting()
              result.success(true)
          }
          "stopBroadcasting" -> {
              stopBroadcasting()
              result.success(true)
          }
          "updateBpm" -> {
              val bpm = call.argument<Int>("bpm") ?: 0
              updateBpm(bpm)
              result.success(true)
          }
          else -> result.notImplemented()
      }
  }

}