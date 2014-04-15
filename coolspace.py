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
    apidir = SESSION.get('http://spaceapi.net/directory.json?api=0.13').json()
    for url in sorted(apidir.itervalues()):
        try:
            api_data = SESSION.get(url).json()
        except IOError:
            pass
        else:
            for temperature in api_data.get('sensors', {}).get('temperature', []):
                temperature['space'] = api_data['space']
                temperature['value'] = float(temperature['value'])
                name = temperature.get('name')
                if name is not None:
                    temperature['location'] += ' ({0})'.format(name)
                yield temperature

def gen_temps():
    temps = sorted(gen_temperatures(), key=itemgetter('value'), reverse=True)
    lengths = defaultdict(int)
    for temp in temps:
        for k, v in temp.iteritems():
            lengths[k] = max(lengths[k], len(unicode(v)))

    for temp in temps:
        gauge = '=' * int(temp['value'] * 2)
        yield '   '.join(unicode(temp.get(k, '')).ljust(lengths[k])
            for k in ('space', 'location', 'value')) + '   ' + gauge

if __name__ == '__main__':
    print(os.linesep.join(gen_temps()))
