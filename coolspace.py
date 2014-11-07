#!/usr/bin/env python

from __future__ import print_function, unicode_literals, division
from operator import itemgetter
from collections import defaultdict
import os, requests

STATUS_DIR = "statuses"
SESSION = requests.session()
SESSION.verify = False
SESSION.headers = {'User-Agent': 'https://github.com/dnet/coolspace'}

def gen_temperatures():
    apidir = SESSION.get('http://spaceapi.net/directory.json?filter=sensors').json()
    for url in sorted(apidir.itervalues()):
        try:
            api_data = SESSION.get(url).json()
        except IOError:
            pass
        else:
            for temperature in parse_temps(api_data):
                temperature['space'] = api_data['space']
                try:
                    temperature['value'] = float(temperature['value'])
                except ValueError:
                    from sys import stderr
                    print('Invalid temperature: {0} (URL: {1})'.format(repr(temperature), url), file=stderr)
                    continue
                if temperature['unit'].endswith(u"F"):
                    temperature['value'] = (temperature['value'] - 32) * 5 / 9
                name = temperature.get('name')
                if name is not None:
                    temperature['location'] += ' ({0})'.format(name)
                yield temperature

def parse_temps(api_data):
    version = api_data['api']
    if version == '0.12':
        sensors = api_data.get('sensors')
        if not sensors:
            return
        if isinstance(sensors, list):
            sensors = sensors[0]
        for key, value in sensors.iteritems():
            if key.startswith('temp'):
                for tk, tv in value.iteritems():
                    yield {'location': tk, 'value': tv[:-1], 'unit': tv[-1]}
    elif version == '0.13':
        for temperature in api_data.get('sensors', {}).get('temperature', []):
            yield temperature

def gen_temps():
    temps = sorted(gen_temperatures(), key=itemgetter('value'), reverse=True)
    lengths = defaultdict(int)
    for temp in temps:
        for k, v in temp.iteritems():
            lengths[k] = max(lengths[k], len(unicode(v)))

    for temp in temps:
        gauge = '=' * int(temp['value'] * 2)
        row = '   '.join(unicode(temp.get(k, '')).ljust(lengths[k])
            for k in ('space', 'location', 'value')) + '   ' + gauge
        yield row.encode('utf-8')

if __name__ == '__main__':
    print(os.linesep.join(gen_temps()))
