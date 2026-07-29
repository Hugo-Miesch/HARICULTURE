#!/usr/bin/env python3
import json
import os
import sys
import time

import gpiod
from smbus2 import SMBus, i2c_msg


def env_int(name, default):
    return int(os.getenv(name, str(default)))


def env_bool(name, default=False):
    value = os.getenv(name)
    if value is None:
        return default
    return value.lower() in ("1", "true", "yes", "on")


class HardwareBridge:
    def __init__(self):
        self.chip_number = env_int("GPIO_CHIP", 0)
        self.chip = gpiod.Chip(f"gpiochip{self.chip_number}")
        self.dht_pin = env_int("DHT11_PIN", 24)
        self.soil_pin = env_int("SOIL_SENSOR_PIN", 25)
        self.soil_wet_level = env_int("SOIL_WET_LEVEL", 0)
        self.i2c_bus_number = env_int("BH1750_I2C_BUS", 1)
        self.bh1750_address = env_int("BH1750_ADDRESS", 0x23)
        self.outputs = {
            "irrigation": (
                env_int("PUMP_PIN", 18),
                env_bool("PUMP_ACTIVE_LOW", False),
            ),
            "light": (
                env_int("LIGHT_PIN", 23),
                env_bool("LIGHT_ACTIVE_LOW", False),
            ),
            "ventilation": (
                env_int("VENTILATION_PIN", 17),
                env_bool("VENTILATION_ACTIVE_LOW", False),
            ),
        }

        self.output_lines = {}
        for actuator, (pin, active_low) in self.outputs.items():
            inactive_level = 1 if active_low else 0
            line = self.chip.get_line(pin)
            line.request(
                consumer="hariculture",
                type=gpiod.LINE_REQ_DIR_OUT,
                default_vals=[inactive_level],
            )
            self.output_lines[actuator] = line
        self.soil_line = self.chip.get_line(self.soil_pin)
        self.soil_line.request(
            consumer="hariculture",
            type=gpiod.LINE_REQ_DIR_IN,
        )

    def set_actuator(self, actuator, state):
        if actuator not in self.outputs:
            raise ValueError(f"Actionneur inconnu: {actuator}")
        pin, active_low = self.outputs[actuator]
        electrical_level = int(not state) if active_low else int(state)
        self.output_lines[actuator].set_value(electrical_level)
        return {
            "actuator": actuator,
            "state": bool(state),
            "pin": pin,
            "electricalLevel": electrical_level,
            "appliedAt": time.time(),
        }

    def read_dht11_once(self):
        line = self.chip.get_line(self.dht_pin)
        try:
            line.request(
                consumer="hariculture-dht11",
                type=gpiod.LINE_REQ_DIR_OUT,
                default_vals=[0],
            )
        except Exception as error:
            raise RuntimeError(f"Réservation sortie DHT11 impossible: {error}")
        time.sleep(0.020)
        line.set_value(1)
        time.sleep(0.00004)
        line.release()
        line = self.chip.get_line(self.dht_pin)
        try:
            line.request(
                consumer="hariculture-dht11",
                type=gpiod.LINE_REQ_EV_BOTH_EDGES,
                flags=gpiod.LINE_REQ_FLAG_BIAS_PULL_UP,
            )
        except Exception as error:
            raise RuntimeError(f"Réservation événements DHT11 impossible: {error}")
        edges = []
        deadline = time.monotonic() + 0.100
        while time.monotonic() < deadline and len(edges) < 84:
            try:
                remaining_ns = int(max(0, deadline - time.monotonic()) * 1_000_000_000)
                if not line.event_wait(remaining_ns // 1_000_000_000, remaining_ns % 1_000_000_000):
                    break
                event = line.event_read()
            except Exception as error:
                line.release()
                raise RuntimeError(f"Lecture événements DHT11 impossible: {error}")
            level = 1 if event.type == gpiod.LineEvent.RISING_EDGE else 0
            edges.append((level, event.sec * 1_000_000_000 + event.nsec))
        line.release()

        high_pulses = []
        rising_at = None
        for level, timestamp in edges:
            if level == 1:
                rising_at = timestamp
            elif level == 0 and rising_at is not None:
                high_pulses.append((timestamp - rising_at) / 1000)
                rising_at = None

        if len(high_pulses) < 40:
            raise RuntimeError("Réponse DHT11 incomplète")
        data_pulses = high_pulses[-40:]
        bits = [1 if width_us > 50 else 0 for width_us in data_pulses]
        values = []
        for offset in range(0, 40, 8):
            value = 0
            for bit in bits[offset : offset + 8]:
                value = (value << 1) | bit
            values.append(value)
        if (sum(values[:4]) & 0xFF) != values[4]:
            raise RuntimeError("Checksum DHT11 invalide")

        humidity = values[0] + values[1] / 10
        temperature = values[2] + (values[3] & 0x7F) / 10
        if values[3] & 0x80:
            temperature = -temperature
        return temperature, humidity

    def read_dht11(self):
        errors = []
        for _attempt in range(3):
            try:
                return self.read_dht11_once()
            except Exception as error:
                errors.append(str(error))
                time.sleep(1)
        raise RuntimeError(" | ".join(errors))

    def read_bh1750(self):
        with SMBus(self.i2c_bus_number) as bus:
            write = i2c_msg.write(self.bh1750_address, [0x20])
            bus.i2c_rdwr(write)
            time.sleep(0.180)
            read = i2c_msg.read(self.bh1750_address, 2)
            bus.i2c_rdwr(read)
            raw = list(read)
        return round(((raw[0] << 8) | raw[1]) / 1.2, 2)

    def read_sensors(self):
        result = {}
        errors = {}
        try:
            result["temperature"], result["airHumidity"] = self.read_dht11()
        except Exception as error:
            errors["dht11"] = str(error)
        try:
            result["lightLevel"] = self.read_bh1750()
        except Exception as error:
            errors["bh1750"] = str(error)
        try:
            level = self.soil_line.get_value()
            wet = level == self.soil_wet_level
            result["soilHumidity"] = 100 if wet else 0
            result["soilWet"] = wet
        except Exception as error:
            errors["soil"] = str(error)
        if not result:
            raise RuntimeError(f"Aucun capteur disponible: {errors}")
        result["sensorErrors"] = errors
        return result

    def close(self):
        for actuator in self.outputs:
            try:
                self.set_actuator(actuator, False)
            except Exception:
                pass
        self.soil_line.release()
        for line in self.output_lines.values():
            line.release()
        self.chip.close()


def send(payload):
    print(json.dumps(payload, separators=(",", ":")), flush=True)


bridge = None
try:
    bridge = HardwareBridge()
    send({"event": "ready"})
    for line in sys.stdin:
        request = json.loads(line)
        request_id = request.get("id")
        try:
            if request["command"] == "setActuator":
                data = bridge.set_actuator(request["actuator"], request["state"])
            elif request["command"] == "readSensors":
                data = bridge.read_sensors()
            elif request["command"] == "shutdown":
                send({"id": request_id, "ok": True, "data": {}})
                break
            else:
                raise ValueError("Commande matérielle inconnue")
            send({"id": request_id, "ok": True, "data": data})
        except Exception as error:
            send({"id": request_id, "ok": False, "error": str(error)})
except Exception as error:
    send({"event": "fatal", "error": str(error)})
    sys.exit(1)
finally:
    if bridge is not None:
        bridge.close()
