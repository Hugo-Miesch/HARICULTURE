import { Routine } from '../models/Routine.js';
import { Greenhouse } from '../models/Greenhouse.js';
import { hardware } from './hardware.js';

let timer;
const runningStops = new Set();

async function tick() {
  const now = new Date();
  const time = `${String(now.getHours()).padStart(2, '0')}:${String(now.getMinutes()).padStart(2, '0')}`;
  const startOfMinute = new Date(now);
  startOfMinute.setSeconds(0, 0);

  const routines = await Routine.find({
    enabled: true,
    time,
    days: now.getDay(),
    $or: [{ lastRunAt: { $lt: startOfMinute } }, { lastRunAt: null }]
  });

  for (const routine of routines) {
    const greenhouse = await Greenhouse.findById(routine.greenhouse);
    if (!greenhouse) continue;
    await hardware.setActuator(greenhouse.id, routine.actuator, true, routine.value);
    greenhouse.actuators[routine.actuator] = {
      state: true,
      value: routine.value,
      updatedAt: now
    };
    routine.lastRunAt = now;
    await Promise.all([greenhouse.save(), routine.save()]);

    const stop = setTimeout(async () => {
      await hardware.setActuator(greenhouse.id, routine.actuator, false, 0);
      await Greenhouse.updateOne(
        { _id: greenhouse.id },
        { [`actuators.${routine.actuator}`]: { state: false, value: 0, updatedAt: new Date() } }
      );
      runningStops.delete(stop);
    }, routine.durationSeconds * 1000);
    runningStops.add(stop);
  }
}

export function startRoutineScheduler() {
  if (!timer) timer = setInterval(() => tick().catch(console.error), 30_000);
}

export function stopRoutineScheduler() {
  if (timer) clearInterval(timer);
  for (const stop of runningStops) clearTimeout(stop);
  timer = undefined;
  runningStops.clear();
}
