import math
import sys

f = open("/Users/daniele/Dev/ds/erlang/config/berlin52.tsp", "r")
nodes = [] # [id, coord_x, coord_y]
edges = [] 

for line in f.readlines():
    node = line.split(" ")  
    nodes.append(node)

for index, node in enumerate(nodes):
    if index != len(nodes) - 1:
        node[2] = node[2][0:len(node[2])-1]     # per rimuovere il \n che c'e' a fine di ogni riga

for node in nodes:
    node[0] = int(node[0])
    node[1] = float(node[1])
    node[2] = float(node[2])

# print(nodes)
for i in range(0, len(nodes)):
    for j in range(i+1, len(nodes)):
        edge = [(i+1, j+1), round(math.sqrt((nodes[i][1] - nodes[j][1])**2 + (nodes[i][2] - nodes[j][2])**2), 2)]
        edges.append(edge)

sum = 0 
for edge in edges:
    sum += edge[1]

print(sum / len(edges))

# aco_node:add_local_node(#node{name=1}).
#edge{from=#node{name=1}, to=#node{name=2}, weight=1}
with open("config_52_nodes.txt", "w") as f:
    sys.stdout = f
    print("""c(aco_node, debug_info).
c(ant_colony, debug_info).
net_adm:ping('A2@Computer').
aco_node:start_link().
rr(aco_node).\n""")

    for idx, node in enumerate(nodes):
        if idx != 0 and idx % 17 == 0:
            print(f"aco_node:add_local_node(#node{{name={node[0]}}}).\n")
        else:
            print(f"aco_node:add_local_node(#node{{name={node[0]}}}).")

    print("")
    for idx, edge in enumerate(edges):
        if idx == 0:
            print(f"aco_node:add_local_edges([#edge{{from=#node{{name={edge[0][0]}}}, to=#node{{name={edge[0][1]}}}, weight={edge[1]}}}", end=", ")
        elif idx == len(edges)-1:
            print(f"#edge{{from=#node{{name={edge[0][0]}}}, to=#node{{name={edge[0][1]}}}, weight={edge[1]}}}", end="]).")
        else:
            print(f"#edge{{from=#node{{name={edge[0][0]}}}, to=#node{{name={edge[0][1]}}}, weight={edge[1]}}}", end=", ")
