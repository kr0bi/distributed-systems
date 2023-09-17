#!/usr/bin/env python3

from flask import Flask, render_template, jsonify, request, send_file
import multiprocessing
from backend import Backend

app = Flask(__name__)
app.config['TEMPLATES_AUTO_RELOAD'] = True
bk = Backend()
counter = 4

@app.route("/")
#renders main page
def index():
	# Read Sensors Status
      templateData = {
            'title' : 'ACO System Visualizer',
      }
      return render_template('index.html', **templateData)

@app.route("/graph")
#renders graph page
def graph():
	# Read Sensors Status
      templateData = {
            'title' : 'Graph',
      }
      return render_template('graph.html', **templateData)

@app.route("/update")
#handles automatic updating of graph data
def update():
    templateData = {
            'title' : 'ACO System Visualizer',
      }
    Nodes, Edges, EdgeCosts = bk.getGraphFromFile()
    pathList, costList = bk.getPathFromFile()
    bk.resetGraph()
    bk.addNodes(Nodes)
    if pathList != []:
         bk.drawBestPath(pathList[-1:], costList[-1:])
    bk.addEdges(Edges, EdgeCosts)
    bk.drawGraph()
    return jsonify(templateData), 1000

if __name__ == "__main__":
      manager = multiprocessing.Manager()