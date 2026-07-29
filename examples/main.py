"""An ordinary Python program that grew a Common Lisp module.

Everything here is plain Python.  The one unusual line is `import hyclb`,
which teaches the import system about .lisp files; after that `model_math`
is imported and used like any other module.
"""

import torch

import hyclb  # noqa: F401  -- enables `import model_math` below
import model_math


def compare_gradients(values):
    """Our analytic backward pass against Torch's own autograd."""
    x = torch.tensor(values, requires_grad=True)
    model_math.swish.apply(x).sum().backward()
    ours = x.grad.clone()

    y = torch.tensor(values, requires_grad=True)
    (y * torch.sigmoid(y)).sum().backward()
    theirs = y.grad
    return ours, theirs, torch.allclose(ours, theirs, atol=1e-6)


def main():
    print("swish_scalar(1.0) =", round(model_math.swish_scalar(1.0), 6))
    print("swish_slope(1.0)  =", round(model_math.swish_slope(1.0), 6))
    print("annotations       =", model_math.swish_scalar.__annotations__)

    ours, theirs, agree = compare_gradients([-1.0, 0.0, 1.0, 2.0])
    print("analytic gradient =", [round(v, 6) for v in ours.tolist()])
    print("torch autograd    =", [round(v, 6) for v in theirs.tolist()])
    print("agree             =", agree)

    # and it is a normal module: usable in a normal training loop
    layer = torch.nn.Linear(4, 1)
    opt = torch.optim.SGD(layer.parameters(), lr=0.1)
    data = torch.randn(64, 4)
    target = data.sum(dim=1, keepdim=True)
    for _ in range(200):
        opt.zero_grad()
        loss = ((model_math.swish.apply(layer(data)) - target) ** 2).mean()
        loss.backward()
        opt.step()
    print("final loss        =", round(loss.item(), 4))


if __name__ == "__main__":
    main()
