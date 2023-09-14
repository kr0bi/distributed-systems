#!/usr/bin/env python3

from flask import Flask, render_template, jsonify, request, send_file
import datetime
import time
import sys
import multiprocessing
from backend import Backend
import networkx as nx
from io import BytesIO
import matplotlib.pyplot as plt

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
#handles automatic updating of scale data
def update():
    templateData = {
            'title' : 'ACO System Visualizer',
      }
    Nodes, Edges, EdgeCosts = bk.getGraphFromFile()
    pathList, costList, bestPath = bk.getPathFromFile()
    bk.resetGraph()
    bk.addNodes(Nodes)
    if pathList != []:
         bk.drawBestPath(pathList[bestPath], costList[bestPath])
    bk.addEdges(Edges, EdgeCosts)
    bk.drawGraph()
    return jsonify(templateData), 10000
"""
def initGraph():
        print("Setup started")
        graph.add_nodes_from([(3, {"color": "red"}),
                                   (4, {"color": "green"}),
                                   (5, {"color": "blue"})])
        graph.add_edges_from([(3,4), (4,5)])
        print("Setup finished") 

@app.route("/graph")
def drawGraph():
        bk.drawGraph()
        return send_file("images/graph.png", mimetype='image/png')"""

if __name__ == "__main__":
      manager = multiprocessing.Manager()