import numpy as np
import scipy

a = 0.367879441171442322
b = 3.367879441171442322
precision_slots = 128
step = (b - a) / precision_slots

# slots = np.arange(a, b, step)
slots = np.linspace(a, b, precision_slots+1, endpoint=True)
print(slots)
for i, x in enumerate(slots):
    res = np.real(scipy.special.lambertw(i))
    integerRes = int(f"{res:.18f}".replace(".", ""))
    # print(f"W({i}) = {res}")
    print(f"lambertArray[{i}] = {integerRes};")

print(len(slots))