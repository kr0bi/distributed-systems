#!/usr/bin/env python3

import networkx as nx
from io import BytesIO
import matplotlib.pyplot as plt
from pyvis.network import Network
from flask import Flask, render_template, jsonify, request, send_file
from xml.dom.minidom import parse, parseString
import os.path
import xml


class Backend:

    ### Initializes backend object
    def __init__(self):
        self.net = Network()

    # Returns nodes and edges read from the XML file
    def getGraphFromFile(self):
        path = os.path.dirname(os.path.dirname(__file__)) + '/erlang/graph.xml'
        edgeList = []
        edgeCostList = []
        nodeList = []
        ## try catch if the xml file is empty
        try:
            document = parse(path)
            nodes = document.getElementsByTagName("client")

            for node in nodes:
                nodeList.append(int(node.firstChild.nodeValue))
            edges = document.getElementsByTagName("route")
            
            for edge in edges:
                wEdge = (int(edge.childNodes[0].firstChild.nodeValue), int(edge.childNodes[1].firstChild.nodeValue))
                edgeCostList.append(int(edge.childNodes[2].firstChild.nodeValue))
                edgeList.append(wEdge)
        except xml.parsers.expat.ExpatError:
            pass
        return nodeList, edgeList, edgeCostList
    
    ## Returns the latest best path read from the path XML file
    def getPathFromFile(self):
        path = os.path.dirname(os.path.dirname(__file__)) + '/erlang/path.xml'
        # variable init
        costList = []
        pathList = []
        nodeList = []
        bestCost = 1000000
        counter = 0
        bestPath = 0
        ## try catch if the xml file is empty
        try :
            document = parse(path)
            nodes = document.getElementsByTagName("path")
            for node in nodes: ## loops on all paths found
                nodeList = []
                for client in node.childNodes: ## loops on all nodes
                    if client == node.lastChild: ## checks if it arrived at the cost node
                        Cost = int(client.firstChild.nodeValue)
                        costList.append(Cost)
                    else:
                        nodeList.append(int(client.firstChild.nodeValue))
                pathList.append(nodeList)
                counter = counter + 1
            for i in range(len(costList)): ## checks for best path, needs to have the same nodes as the latest path received
                if ((costList[i] < bestCost) and 
                    ((pathList[i].sort() == pathList[len(pathList)-1].sort()) and 
                     (len(pathList[i]) == len(pathList[len(pathList)-1])) )):
                    bestPath = i
                    bestCost = costList[i]
        except xml.parsers.expat.ExpatError:
            pass
        return pathList, costList, bestPath ## returns the list of paths and their costs and the index of the best path
    

    ## Adds nodes to the graph
    def addNodes(self, Nodes):
        self.net.add_nodes(Nodes, title=list(map(addClientTitle, Nodes))) ## Puts Client + ClientID as the node title

    ## Adds edges to the graph
    def addEdges(self, Edges, Costs):
        for i in range(len(Edges)):
            self.net.add_edge(Edges[i][0], Edges[i][1], title = Costs[i], width = 3) ## Sets the edge cost as the edge title

    ## Resets the graph
    def resetGraph(self):
        self.net = Network()

    ## Draws the graph and saves it to file
    def drawGraph(self):
        self.net.toggle_physics(True)
        self.net.write_html(os.path.dirname(__file__) + '/templates/graph.html', local=True, notebook=False, open_browser=False)

    ## Adds a single node (test function)
    def addNode(self, id):
        self.net.add_node(id, label=id, value=200)
        self.net.add_edge(1, id, weight=id)

    ## Adds the best path to the graph, highlighted in brick red and with edges slightly wider
    def drawBestPath(self, Path, Cost):
        for i in range(len(Path)):
            if i == len(Path) - 1:
                self.net.add_edge(Path[i], Path[0], color='#b22222', title ="Path cost: {}".format(Cost), width = 4)
            else:
                self.net.add_edge(Path[i], Path[i+1], color='#b22222', title ="Path cost: {}".format(Cost), width = 4)

    ## Returns graph nodes
    def getNodes(self):
        self.net.get_nodes()
    
    ## Returns graph edges
    def getEdges(self):
        self.net.get_edges()

    ## Returns whether two graphs are different
    def isDifferent(self, Nodes, Edges):
        return (self.net.get_nodes() != Nodes) or (self.net.get_edges() != Edges) 

## Builds Client title strings
def addClientTitle(node):
        return "Client {}".format(node)

