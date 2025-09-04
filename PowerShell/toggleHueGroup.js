process.env.NODE_TLS_REJECT_UNAUTHORIZED = '0';
process.removeAllListeners('warning');

const [roomName] = process.argv.slice(2);

const child_process = require('child_process');
const path = require('path');

const config = require(path.resolve(__dirname, 'Invoke-Hue.config.json'));

async function sendHueRequest(route = '/', method = 'GET', body = null) {
	return fetch(`https://${config.hostname}/clip/v2${route}`, { method, body, headers: { 'hue-application-key': config.username } }).then(r => r.json());
}

async function getRooms() {
	return sendHueRequest('/resource/room');
}

async function getRoomByName(name) {
	const { data: rooms } = await getRooms();
	return rooms.find(r => r.metadata.name === name);
}

async function getGroupById(id) {
	return sendHueRequest(`/resource/grouped_light/${id}`);
}

async function toggleGroup(group) {
	const newOnValue = !group.on.on;
	const body = JSON.stringify({ on: { on: newOnValue } });
	await sendHueRequest(`/resource/grouped_light/${group.id}`, 'PUT', body);

	child_process.execSync(`ffplay "${path.resolve(newOnValue ? config.on : config.off)}" -nodisp -volume 100 -autoexit`);
}

getRoomByName(roomName)
	.then(async room => {
		const { data: [group] } = await getGroupById(room.services.find(s => s.rtype === 'grouped_light').rid);
		toggleGroup(group);
	});