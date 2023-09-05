#!/usr/bin/env python3

import networkx as nx
from io import BytesIO
import matplotlib.pyplot as plt
from pyvis.network import Network
from flask import Flask, render_template, jsonify, request, send_file
from xml.dom.minidom import parse, parseString
import os.path


class Backend:

    ### Initializes backend object
    # dout = HX711 dt pin, pd_sck = HX711 sck pin, servo_pin = servo motor GPIO pin 
    def __init__(self):
        print("Setup started")
        self.net = Network()
        #self.graph = nx.Graph()
        """self.net.add_nodes([1,2,3], value=[10, 100, 400],
                         title=['I am node 1', 'node 2 here', 'and im node 3'],
                         x=[21.4, 54.2, 11.2],
                         y=[100.2, 23.54, 32.1],
                         label=['NODE 1', 'NODE 2', 'NODE 3'],
                         color=['#00ff1e', '#162347', '#dd4b39'])
        self.net.add_edge(1,2, weight=0.8)
        self.net.add_edge(1,3, weight=0.3)"""
        print("Setup finished")   

    def getGraphFromFile(self):
        path = os.path.dirname(os.path.dirname(__file__)) + '/erlang/graph.xml'
        #print(path)
        document = parse(path)
        nodes = document.getElementsByTagName("client")
        #print(nodes)
        nodeList = []
        for node in nodes:
            nodeList.append(int(node.firstChild.nodeValue))
        edges = document.getElementsByTagName("route")
        edgeList = []
        for edge in edges:
            wEdge = (int(edge.childNodes[0].firstChild.nodeValue), int(edge.childNodes[1].firstChild.nodeValue), int(edge.childNodes[2].firstChild.nodeValue))
            edgeList.append(wEdge)
        
        #print(nodeList)
        #print(edgeList)
        return nodeList, edgeList
        
    def addNodes(self, Nodes):
        self.net.add_nodes(Nodes)

    def addEdges(self, Edges):
        self.net.add_edges(Edges)

    def resetGraph(self):
        self.net = Network()


    def drawGraph(self):
        self.net.toggle_physics(True)
        self.net.write_html(os.path.dirname(__file__) + '/templates/graph.html', local=True, notebook=False, open_browser=False)

    def addNode(self, id):
        self.net.add_node(id, label=id, value=200)
        self.net.add_edge(1, id, weight=id)