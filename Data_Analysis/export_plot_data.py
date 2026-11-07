"""Export the six required plots and their observations using Python's standard library."""
import csv
import json
from pathlib import Path

BASE = Path(__file__).resolve().parent
OUT = BASE / 'plot_exports'
LABELS = ['1 control', '2 25% ascii', '3 50% ascii', '4 75% ascii', '5 100% ascii']
COLORS = ['#636EFA', '#EF553B', '#00CC96', '#AB63FA', '#FFA15A']


def main():
    with (BASE / 'sessions1.csv').open() as file:
        reader = csv.DictReader(file)
        columns = reader.fieldnames + ['config_label']
        rows = []
        for row in reader:
            config = row['config'].removesuffix('.0')
            if config not in ['1', '2', '3', '4', '5']:
                continue
            try:
                float(row['session_seconds'])
            except ValueError:
                continue
            row['config_label'] = LABELS[int(config) - 1]
            rows.append(row)

    def timeout(row):
        return float(row['session_seconds']) >= 300 or row['reason'].strip().lower() in {
            'session timeout', 'kicked at 5 minutes', 'timeout'}

    first = {}
    for row in sorted(rows, key=lambda row: row['timestamp']):
        ip = row['attacker_ip']
        if ip and ip != 'unknown':
            first.setdefault(ip, row)
    unique = list(first.values())
    datasets = [
        ('time_all', 'Time spent per configuration', rows, 'session_seconds'),
        ('time_no_timeouts', 'Time spent excluding timeouts', [r for r in rows if not timeout(r)], 'session_seconds'),
        ('time_unique', 'Time spent, unique IPs', unique, 'session_seconds'),
        ('time_unique_no_timeouts', 'Time spent, unique IPs, excluding timeouts', [r for r in unique if not timeout(r)], 'session_seconds'),
        ('commands_all', 'Number of commands per configuration', rows, 'commands'),
        ('commands_unique', 'Number of commands, unique IPs', unique, 'commands'),
    ]
    OUT.mkdir(exist_ok=True)
    sections = []
    for slug, title, data, metric in datasets:
        data = [r for r in data if r[metric].strip()]
        with (OUT / f'{slug}_points.csv').open('w', newline='') as file:
            writer = csv.DictWriter(file, fieldnames=columns)
            writer.writeheader()
            writer.writerows(data)
        traces = []
        scatter_traces = []
        for label, color in zip(LABELS, COLORS):
            group = [r for r in data if r['config_label'] == label]
            traces.append(dict(type='violin', name=label,
                x=[label] * len(group), y=[float(r[metric]) for r in group],
                box=dict(visible=True), points=False, width=0.85,
                marker=dict(color=color), line=dict(color=color, width=2),
                spanmode='hard', scalemode='width',
                customdata=[[r['timestamp'], r['honeypot'], r['attacker_ip']] for r in group],
                xaxis='x', yaxis='y',
                hovertemplate='%{x}<br>Value: %{y}<br>%{customdata[0]}<br>%{customdata[1]}<br>IP: %{customdata[2]}<extra></extra>'))
            position = LABELS.index(label)
            jitter = [(((index * 37) % 101) / 100 - 0.5) * 0.4 for index in range(len(group))]
            scatter_traces.append(dict(type='scatter', mode='markers', name=label,
                x=[position + offset for offset in jitter],
                y=[float(r[metric]) for r in group],
                marker=dict(size=5, opacity=0.55, color=color),
                customdata=[[r['timestamp'], r['honeypot'], r['attacker_ip']] for r in group],
                xaxis='x2', yaxis='y2',
                hovertemplate=f'{label}<br>Value: %{{y}}<br>%{{customdata[0]}}<br>%{{customdata[1]}}<br>IP: %{{customdata[2]}}<extra></extra>'))
        traces.extend(scatter_traces)
        layout = dict(title=f'{title} (n={len(data)})', height=650, width=1500, autosize=False, violinmode='overlay', violingap=0, showlegend=False,
            plot_bgcolor='#E5ECF6', paper_bgcolor='white', font=dict(family='Arial'),
            xaxis=dict(domain=[0, 0.47], categoryorder='array', categoryarray=LABELS, title='Honeypot configuration'),
            xaxis2=dict(domain=[0.55, 1], range=[-0.5, len(LABELS) - 0.5],
                        tickmode='array', tickvals=list(range(len(LABELS))), ticktext=LABELS,
                        title='Honeypot configuration'),
            yaxis=dict(title='Time spent (seconds)' if metric == 'session_seconds' else 'Number of commands',
                       rangemode='tozero', gridcolor='white', zerolinecolor='white', domain=[0, 0.9]),
            yaxis2=dict(matches='y', showticklabels=False, gridcolor='white', zerolinecolor='white',
                        domain=[0, 0.9]),
            annotations=[
                dict(text='Distribution', x=0.235, y=1.04, xref='paper', yref='paper', showarrow=False),
                dict(text='Individual observations', x=0.775, y=1.04, xref='paper', yref='paper', showarrow=False),
            ])
        sections.append(f'<div id="{slug}" style="width:1500px;height:650px"></div><p><a href="{slug}_points.csv">Download plotted observations (CSV)</a></p><script>Plotly.newPlot({json.dumps(slug)}, {json.dumps(traces)}, {json.dumps(layout)}, {{responsive:false}});</script>')
        print(f'{slug}: {len(data)} observations')
    (OUT / 'plots.html').write_text('<!doctype html><html><head><meta charset="utf-8"><title>Honeypot plots</title><script src="https://cdn.plot.ly/plotly-2.35.2.min.js"></script></head><body style="margin:24px;min-width:1200px"><h1>Honeypot observations by configuration</h1><p>Every point is an observed session. Unique IP plots keep the earliest session per IP. Excluding timeouts removes the five-minute limit; idle timeouts remain. Vertical axes use the original units.</p>' + '\n'.join(sections) + '</body></html>')


if __name__ == '__main__':
    main()
